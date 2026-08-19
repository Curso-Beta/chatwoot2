<script setup>
import { computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Banner from 'dashboard/components-next/banner/Banner.vue';

const store = useStore();
const router = useRouter();
const { isAdmin } = useAdmin();

const inboxes = useMapGetter('inboxes/getInboxes');

onMounted(() => {
  store.dispatch('inboxes/get');
});

const disconnectedInboxes = computed(() => {
  return (inboxes.value || []).filter(i => i.reauthorization_required);
});

const hasDisconnected = computed(() => disconnectedInboxes.value.length > 0);

const bannerMessage = computed(() => {
  const names = disconnectedInboxes.value.map(i => i.name).join(', ');
  if (disconnectedInboxes.value.length === 1) {
    return `A caixa de entrada "${names}" está desconectada e não receberá novas mensagens.`;
  }
  return `As caixas de entrada ${names} estão desconectadas e não receberão novas mensagens.`;
});

const goToInboxes = () => {
  router.push({ name: 'settings_inbox_list' });
};
</script>

<template>
  <Banner
    v-if="isAdmin && hasDisconnected"
    color="ruby"
    action-label="Ver caixas de entrada"
    class="!rounded-none !justify-center"
    @action="goToInboxes"
  >
    <span class="text-xs">{{ bannerMessage }}</span>
  </Banner>
</template>
