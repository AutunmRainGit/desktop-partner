// A deliberately small, optional GDExtension: only styles the menu's own OS window.
#include "gdextension_interface.h"
#include <cstdint>

#ifdef __APPLE__
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#elif defined(_WIN32)
#include <windows.h>
#include <dwmapi.h>
#endif

static bool apply_glass(int64_t handle) {
    if (!handle) return false;
#ifdef __APPLE__
    if (![NSThread isMainThread]) return false;
    NSWindow *window = (__bridge NSWindow *)(reinterpret_cast<void *>(handle));
    NSView *content = window.contentView;
    if (!content) return false;
    for (NSView *view in content.subviews) {
        if ([view.identifier isEqualToString:@"DesktopPartnerGlass"]) return true;
    }
    NSVisualEffectView *glass = [[NSVisualEffectView alloc] initWithFrame:NSInsetRect(content.bounds, 8, 8)];
    glass.identifier = @"DesktopPartnerGlass";
    glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    glass.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    glass.material = NSVisualEffectMaterialPopover;
    glass.state = NSVisualEffectStateActive;
    glass.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    glass.alphaValue = 0.60;
    glass.wantsLayer = YES;
    glass.layer.cornerRadius = 14;
    glass.layer.masksToBounds = YES;
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.hasShadow = YES;
    [content addSubview:glass positioned:NSWindowBelow relativeTo:nil];
    return true;
#elif defined(_WIN32)
    HWND window = reinterpret_cast<HWND>(handle);
    if (!IsWindow(window)) return false;
    // Windows 11 22H2+: DWMWA_SYSTEMBACKDROP_TYPE / DWMSBT_TRANSIENTWINDOW.
    // Older systems return failure and keep the transparent CSS fallback.
    const int backdrop = 3;
    HRESULT result = DwmSetWindowAttribute(window, 38, &backdrop, sizeof(backdrop));
    if (FAILED(result)) return false;
    const int corner = 2;
    DwmSetWindowAttribute(window, 33, &corner, sizeof(corner));
    MARGINS margins = {-1, -1, -1, -1};
    DwmExtendFrameIntoClientArea(window, &margins);
    return true;
#else
    return false;
#endif
}

static GDExtensionInterfaceGetProcAddress api;
static GDExtensionClassLibraryPtr library;
static GDExtensionInterfaceStringNameNewWithUtf8Chars make_name;
static GDExtensionPtrDestructor destroy_name;
static GDExtensionInterfaceClassdbConstructObject construct_object;
static GDExtensionInterfaceObjectSetInstance set_instance;
static GDExtensionInterfaceVariantGetType variant_type;
static GDExtensionVariantFromTypeConstructorFunc make_bool;
static GDExtensionTypeFromVariantConstructorFunc read_int;
alignas(8) static uint8_t class_name[32];
alignas(8) static uint8_t parent_name[32];

struct Instance {};
static GDExtensionObjectPtr create_instance(void *) {
    auto object = construct_object(parent_name);
    set_instance(object, class_name, new Instance);
    return object;
}
static void free_instance(void *, GDExtensionClassInstancePtr instance) {
    delete static_cast<Instance *>(instance);
}

static void call_apply(void *, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args,
        GDExtensionInt count, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    GDExtensionBool success = false;
    error->error = GDEXTENSION_CALL_OK;
    if (count != 1 || variant_type(args[0]) != GDEXTENSION_VARIANT_TYPE_INT) {
        error->error = count < 1 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : count > 1 ? GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS : GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        error->argument = 0;
        error->expected = GDEXTENSION_VARIANT_TYPE_INT;
    } else {
        int64_t handle = 0;
        read_int(&handle, const_cast<GDExtensionVariantPtr>(args[0]));
        success = apply_glass(handle);
    }
    make_bool(result, &success);
}

static void initialize(void *, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    make_name = reinterpret_cast<GDExtensionInterfaceStringNameNewWithUtf8Chars>(api("string_name_new_with_utf8_chars"));
    destroy_name = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"))(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    construct_object = reinterpret_cast<GDExtensionInterfaceClassdbConstructObject>(api("classdb_construct_object"));
    set_instance = reinterpret_cast<GDExtensionInterfaceObjectSetInstance>(api("object_set_instance"));
    variant_type = reinterpret_cast<GDExtensionInterfaceVariantGetType>(api("variant_get_type"));
    make_bool = reinterpret_cast<GDExtensionInterfaceGetVariantFromTypeConstructor>(api("get_variant_from_type_constructor"))(GDEXTENSION_VARIANT_TYPE_BOOL);
    read_int = reinterpret_cast<GDExtensionInterfaceGetVariantToTypeConstructor>(api("get_variant_to_type_constructor"))(GDEXTENSION_VARIANT_TYPE_INT);
    make_name(class_name, "DesktopGlass");
    make_name(parent_name, "RefCounted");
    GDExtensionClassCreationInfo2 info = {};
    info.is_exposed = true;
    info.create_instance_func = create_instance;
    info.free_instance_func = free_instance;
    reinterpret_cast<GDExtensionInterfaceClassdbRegisterExtensionClass2>(api("classdb_register_extension_class2"))(library, class_name, parent_name, &info);
    alignas(8) uint8_t method_name[32], argument_name[32], empty_name[32];
    make_name(method_name, "apply");
    make_name(argument_name, "window_handle");
    make_name(empty_name, "");
    alignas(8) uint8_t empty_string[32];
    reinterpret_cast<GDExtensionInterfaceStringNewWithUtf8Chars>(api("string_new_with_utf8_chars"))(empty_string, "");
    GDExtensionPropertyInfo returned = {};
    returned.type = GDEXTENSION_VARIANT_TYPE_BOOL;
    returned.name = returned.class_name = empty_name;
    returned.hint_string = empty_string;
    GDExtensionPropertyInfo argument = {};
    argument.type = GDEXTENSION_VARIANT_TYPE_INT;
    argument.name = argument_name;
    argument.class_name = empty_name;
    argument.hint_string = empty_string;
    GDExtensionClassMethodArgumentMetadata metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
    GDExtensionClassMethodInfo method = {};
    method.name = method_name;
    method.call_func = call_apply;
    method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
    method.has_return_value = true;
    method.return_value_info = &returned;
    method.argument_count = 1;
    method.arguments_info = &argument;
    method.arguments_metadata = &metadata;
    reinterpret_cast<GDExtensionInterfaceClassdbRegisterExtensionClassMethod>(api("classdb_register_extension_class_method"))(library, class_name, &method);
    destroy_name(method_name); destroy_name(argument_name); destroy_name(empty_name);
    reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"))(GDEXTENSION_VARIANT_TYPE_STRING)(empty_string);
}

static void deinitialize(void *, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    reinterpret_cast<GDExtensionInterfaceClassdbUnregisterExtensionClass>(api("classdb_unregister_extension_class"))(library, class_name);
    destroy_name(class_name); destroy_name(parent_name);
}

#ifdef _WIN32
#define GLASS_EXPORT __declspec(dllexport)
#else
#define GLASS_EXPORT __attribute__((visibility("default")))
#endif
extern "C" GLASS_EXPORT GDExtensionBool desktop_glass_init(GDExtensionInterfaceGetProcAddress get_api,
        GDExtensionClassLibraryPtr handle, GDExtensionInitialization *initialization) {
    api = get_api; library = handle;
    initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    initialization->initialize = initialize;
    initialization->deinitialize = deinitialize;
    return true;
}
