<script setup>
import { computed, h, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useImpersonation } from 'dashboard/composables/useImpersonation';
import wootConstants from 'dashboard/constants/globals';
import AgentAvailabilityAPI from 'dashboard/api/agentAvailability';
import {
  DropdownContainer,
  DropdownBody,
  DropdownItem,
} from 'next/dropdown-menu/base';

const { t } = useI18n();
const store = useStore();
const { isImpersonating } = useImpersonation();
const { AVAILABILITY_STATUS_KEYS } = wootConstants;

const currentUser = useMapGetter('getCurrentUser');
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');
const currentAccountId = useMapGetter('getCurrentAccountId');

const STATUS_STYLES = {
  online: {
    dot: 'bg-n-teal-9',
    band: 'bg-n-teal-3 border-n-teal-6',
    title: 'text-n-teal-12',
    meta: 'text-n-teal-11',
  },
  busy: {
    dot: 'bg-n-amber-9',
    band: 'bg-n-amber-3 border-n-amber-6',
    title: 'text-n-amber-12',
    meta: 'text-n-amber-11',
  },
  offline: {
    dot: 'bg-n-slate-9',
    band: 'bg-n-slate-3 border-n-slate-6',
    title: 'text-n-slate-12',
    meta: 'text-n-slate-11',
  },
};

const statuses = computed(() =>
  AVAILABILITY_STATUS_KEYS.map(key => ({
    key,
    label: t(`PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.${key.toUpperCase()}`),
    icon: h('span', {
      class: [STATUS_STYLES[key].dot, 'size-2.5 rounded-full'],
    }),
  }))
);

const currentKey = computed(() =>
  STATUS_STYLES[currentUserAvailability.value]
    ? currentUserAvailability.value
    : 'offline'
);
const currentStyle = computed(() => STATUS_STYLES[currentKey.value]);

const logs = ref([]);
const now = ref(Date.now());

const onlineTodayMinutes = computed(() => {
  const userId = currentUser.value?.id;
  const mine = logs.value
    .filter(log => log.user_id === userId)
    .map(log => ({
      at: new Date(log.created_at).getTime(),
      status: log.availability,
    }))
    .sort((a, b) => a.at - b.at);
  if (!mine.length) return null;
  const midnight = new Date(now.value).setHours(0, 0, 0, 0);
  let current = null;
  let total = 0;
  mine.forEach(log => {
    if (current?.status === 'online') {
      total += Math.max(0, log.at - Math.max(current.at, midnight));
    }
    current = log;
  });
  if (current?.status === 'online') {
    total += Math.max(0, now.value - Math.max(current.at, midnight));
  }
  return Math.floor(total / 60000);
});

const onlineTodayLabel = computed(() => {
  const minutes = onlineTodayMinutes.value;
  if (minutes === null) return '—';
  const hours = Math.floor(minutes / 60);
  const rest = String(minutes % 60).padStart(2, '0');
  return hours ? `${hours}h${rest}` : `${minutes} min`;
});

async function fetchHistory() {
  try {
    const { data } = await AgentAvailabilityAPI.history(7);
    logs.value = Array.isArray(data) ? data : [];
  } catch {
    logs.value = [];
  }
}

function changeStatus(availability) {
  if (availability === currentUserAvailability.value) return;
  if (isImpersonating.value) {
    useAlert(t('PROFILE_SETTINGS.FORM.AVAILABILITY.IMPERSONATING_ERROR'));
    return;
  }
  store.dispatch('updateAvailability', {
    availability,
    account_id: currentAccountId.value,
  });
}

let tickTimer;
let fetchTimer;
onMounted(() => {
  fetchHistory();
  tickTimer = setInterval(() => {
    now.value = Date.now();
  }, 60000);
  fetchTimer = setInterval(fetchHistory, 5 * 60000);
});
onBeforeUnmount(() => {
  clearInterval(tickTimer);
  clearInterval(fetchTimer);
});

watch([currentUserAvailability, currentAccountId], () => {
  setTimeout(fetchHistory, 1500);
});
</script>

<template>
  <div
    class="flex items-center justify-between gap-2 w-full px-3 py-2 border-y"
    :class="currentStyle.band"
    role="status"
  >
    <span
      class="flex items-center gap-1.5 min-w-0 text-sm font-medium truncate"
      :class="currentStyle.title"
    >
      <span
        class="size-2.5 rounded-full flex-shrink-0"
        :class="currentStyle.dot"
      />
      {{ $t(`SIDEBAR.STATUS_BAR.TITLE.${currentKey.toUpperCase()}`) }}
    </span>
    <DropdownContainer class="flex-shrink-0">
      <template #trigger="{ toggle }">
        <button
          type="button"
          class="flex items-center gap-1 text-xs whitespace-nowrap rounded-md px-1 -mx-1 hover:bg-n-alpha-1"
          :class="currentStyle.meta"
          :aria-label="$t('SIDEBAR.SET_YOUR_AVAILABILITY')"
          @click="toggle"
        >
          <span class="tabular-nums">
            {{ $t('SIDEBAR.STATUS_BAR.TODAY', { time: onlineTodayLabel }) }}
          </span>
          <span aria-hidden="true">·</span>
          <span class="font-medium">{{ $t('SIDEBAR.STATUS_BAR.CHANGE') }}</span>
          <span class="i-lucide-chevron-down size-3" aria-hidden="true" />
        </button>
      </template>
      <DropdownBody class="bottom-6 z-50 min-w-36 ltr:right-0 rtl:left-0">
        <DropdownItem
          v-for="status in statuses"
          :key="status.key"
          :label="status.label"
          :icon="status.icon"
          class="cursor-pointer"
          @click="changeStatus(status.key)"
        />
      </DropdownBody>
    </DropdownContainer>
  </div>
</template>
