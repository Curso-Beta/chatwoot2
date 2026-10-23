<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useImpersonation } from 'dashboard/composables/useImpersonation';
import wootConstants from 'dashboard/constants/globals';
import AgentAvailabilityAPI from 'dashboard/api/agentAvailability';

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
    active: 'bg-n-teal-3 text-n-teal-11 outline-n-teal-7',
  },
  busy: {
    dot: 'bg-n-amber-9',
    active: 'bg-n-amber-3 text-n-amber-11 outline-n-amber-7',
  },
  offline: {
    dot: 'bg-n-slate-9',
    active: 'bg-n-slate-3 text-n-slate-12 outline-n-slate-7',
  },
};

const statuses = computed(() =>
  AVAILABILITY_STATUS_KEYS.map(key => ({
    key,
    label: t(`PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.${key.toUpperCase()}`),
    ...STATUS_STYLES[key],
  }))
);

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
  const hours = Math.floor(minutes / 60);
  const rest = String(minutes % 60).padStart(2, '0');
  return hours ? `${hours}h${rest}` : `${minutes} min`;
});

async function fetchHistory() {
  try {
    const { data } = await AgentAvailabilityAPI.history(2);
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
  <div class="flex flex-col gap-1.5 px-1 pt-1.5 pb-0.5 w-full">
    <div
      class="grid grid-cols-3 gap-1"
      role="radiogroup"
      :aria-label="$t('SIDEBAR.SET_YOUR_AVAILABILITY')"
    >
      <button
        v-for="status in statuses"
        :key="status.key"
        type="button"
        role="radio"
        :aria-checked="currentUserAvailability === status.key"
        class="flex items-center justify-center gap-1.5 h-7 px-1.5 rounded-md text-xs font-medium transition-colors outline outline-1 -outline-offset-1"
        :class="
          currentUserAvailability === status.key
            ? status.active
            : 'outline-transparent text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="changeStatus(status.key)"
      >
        <span class="size-2 rounded-full flex-shrink-0" :class="status.dot" />
        <span class="truncate">{{ status.label }}</span>
      </button>
    </div>
    <div
      class="flex items-center justify-between px-0.5 text-xs text-n-slate-11"
    >
      <span>{{ $t('SIDEBAR.STATUS_BAR.ONLINE_TODAY') }}</span>
      <span class="font-medium tabular-nums text-n-slate-12">
        {{ onlineTodayLabel }}
      </span>
    </div>
  </div>
</template>
