<script setup>
defineProps({ name: String })
const paths = {
  bread: ['M6 9C1.5 7.5 4 3 8 3h8c4 0 6.5 4.5 2 6v11H6Z'],
  moon: ['M20 14A8 8 0 0 1 10 4a8.4 8.4 0 1 0 10 10Z'],
  sun: ['M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z', 'M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5'],
  book: ['M12 5v15M12 5C9 2 4 3 2 4v15c3-1.5 7-1.5 10 1 3-2.5 7-2.5 10-1V4c-2-1-7-2-10 1Z'],
  monitor: ['M3 3h18v13H3ZM8 21h8m-4-5v5'],
  check: ['m5 12 4 4L19 6'], chevron: ['m9 5 7 7-7 7'], back: ['m13 6-6 6 6 6M7 12h13'],
}
</script>
<template><svg class="menu-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path v-for="(path, index) in paths[name] || []" :key="index" :d="path"/></svg></template>
