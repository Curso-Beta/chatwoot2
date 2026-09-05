<script setup>
import { reactive, computed, watch, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';

const CATEGORIES = [
  { value: 'MARKETING', label: 'Marketing' },
  { value: 'UTILITY', label: 'Utility' },
  { value: 'AUTHENTICATION', label: 'Authentication' },
];

const LANGUAGES = [
  { value: 'pt_BR', label: 'Português (BR)' },
  { value: 'en_US', label: 'English (US)' },
  { value: 'en', label: 'English' },
  { value: 'es', label: 'Español' },
  { value: 'es_AR', label: 'Español (AR)' },
  { value: 'es_MX', label: 'Español (MX)' },
  { value: 'fr', label: 'Français' },
  { value: 'de', label: 'Deutsch' },
  { value: 'it', label: 'Italiano' },
];

const HEADER_FORMATS = [
  { value: 'NONE', label: 'Nenhum' },
  { value: 'TEXT', label: 'Texto' },
  { value: 'IMAGE', label: 'Imagem' },
  { value: 'VIDEO', label: 'Vídeo' },
  { value: 'DOCUMENT', label: 'Documento' },
];

const BUTTON_TYPES = [
  { value: 'QUICK_REPLY', label: 'Resposta Rápida' },
  { value: 'URL', label: 'URL' },
  { value: 'PHONE_NUMBER', label: 'Telefone' },
];

const emit = defineEmits(['created', 'close']);

const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getInboxes');

const panelRef = ref(null);
const isSubmitting = ref(false);

const state = reactive({
  inboxId: null,
  name: '',
  category: 'MARKETING',
  language: 'pt_BR',
  headerFormat: 'NONE',
  headerText: '',
  bodyText: '',
  footerText: '',
  buttons: [],
});

const whatsappCloudInboxes = computed(() =>
  inboxes.value
    .filter(
      inbox =>
        inbox.channel_type === 'Channel::Whatsapp' &&
        inbox.provider === 'whatsapp_cloud'
    )
    .map(inbox => ({ value: inbox.id, label: inbox.name }))
);

const nameError = computed(() => {
  if (!state.name) return '';
  if (!/^[a-z0-9_]+$/.test(state.name))
    return 'Apenas letras minúsculas, números e _';
  if (state.name.length > 512) return 'Máximo 512 caracteres';
  return '';
});

const bodyError = computed(() => {
  if (!state.bodyText) return '';
  if (state.bodyText.length > 1024) return 'Máximo 1024 caracteres';
  return '';
});

const isFormValid = computed(
  () =>
    state.inboxId &&
    state.name &&
    !nameError.value &&
    state.category &&
    state.language &&
    state.bodyText &&
    !bodyError.value
);

const buildComponents = () => {
  const components = [];

  if (state.headerFormat !== 'NONE') {
    const header = { type: 'HEADER', format: state.headerFormat };
    if (state.headerFormat === 'TEXT' && state.headerText) {
      header.text = state.headerText;
    }
    components.push(header);
  }

  components.push({ type: 'BODY', text: state.bodyText });

  if (state.footerText) {
    components.push({ type: 'FOOTER', text: state.footerText });
  }

  if (state.buttons.length > 0) {
    components.push({
      type: 'BUTTONS',
      buttons: state.buttons.map(btn => {
        const button = { type: btn.type, text: btn.text };
        if (btn.type === 'URL') button.url = btn.url;
        if (btn.type === 'PHONE_NUMBER') button.phone_number = btn.phoneNumber;
        return button;
      }),
    });
  }

  return components;
};

const addButton = () => {
  if (state.buttons.length >= 3) return;
  state.buttons.push({ type: 'QUICK_REPLY', text: '', url: '', phoneNumber: '' });
};

const removeButton = index => {
  state.buttons.splice(index, 1);
};

const handleSubmit = async () => {
  if (!isFormValid.value || isSubmitting.value) return;

  isSubmitting.value = true;
  try {
    const payload = {
      name: state.name,
      category: state.category,
      language: state.language,
      components: buildComponents(),
      allow_category_change: true,
    };

    await InboxesAPI.createWhatsappTemplate(state.inboxId, payload);
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.CREATE.SUCCESS'));
    emit('created');
    panelRef.value?.close();
  } catch (error) {
    const errorMessage =
      error?.response?.data?.error?.message ||
      t('WHATSAPP_TEMPLATE_MGMT.CREATE.ERROR');
    useAlert(errorMessage);
  } finally {
    isSubmitting.value = false;
  }
};

const resetForm = () => {
  Object.assign(state, {
    name: '',
    category: 'MARKETING',
    language: 'pt_BR',
    headerFormat: 'NONE',
    headerText: '',
    bodyText: '',
    footerText: '',
    buttons: [],
  });
};

const open = () => {
  resetForm();
  panelRef.value?.open();
};

watch(
  () => state.headerFormat,
  newVal => {
    if (newVal !== 'TEXT') state.headerText = '';
  }
);

defineExpose({ open });
</script>

<template>
  <SidePanel
    ref="panelRef"
    width="lg"
    :title="t('WHATSAPP_TEMPLATE_MGMT.CREATE.TITLE')"
    :description="t('WHATSAPP_TEMPLATE_MGMT.CREATE.DESCRIPTION')"
    @close="emit('close')"
  >
    <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
      <!-- Inbox -->
      <div class="flex flex-col gap-1">
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          Inbox WhatsApp
        </label>
        <ComboBox
          v-model="state.inboxId"
          :options="whatsappCloudInboxes"
          placeholder="Selecione uma inbox"
        />
      </div>

      <!-- Nome do Template -->
      <Input
        v-model="state.name"
        label="Nome do template"
        placeholder="ex: confirmacao_pedido"
        :message="nameError"
        :message-type="nameError ? 'error' : 'info'"
      />
      <p class="mt-[-0.75rem] text-xs text-n-slate-10">
        Apenas letras minúsculas, números e underscore (_)
      </p>

      <!-- Categoria e Idioma -->
      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1">
          <label class="mb-0.5 text-sm font-medium text-n-slate-12">
            Categoria
          </label>
          <ComboBox
            v-model="state.category"
            :options="CATEGORIES"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="mb-0.5 text-sm font-medium text-n-slate-12">
            Idioma
          </label>
          <ComboBox
            v-model="state.language"
            :options="LANGUAGES"
          />
        </div>
      </div>

      <!-- Header -->
      <div class="flex flex-col gap-1">
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          Cabeçalho
        </label>
        <ComboBox
          v-model="state.headerFormat"
          :options="HEADER_FORMATS"
        />
      </div>
      <Input
        v-if="state.headerFormat === 'TEXT'"
        v-model="state.headerText"
        label="Texto do cabeçalho"
        placeholder="Ex: Olá {{1}}!"
      />

      <!-- Body -->
      <div class="flex flex-col gap-1">
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          Corpo da mensagem *
        </label>
        <textarea
          v-model="state.bodyText"
          class="w-full min-h-[120px] px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-1 focus:ring-n-blue-9 resize-y"
          placeholder="Use {{1}}, {{2}} para variáveis. Ex: Olá {{1}}, seu pedido {{2}} foi confirmado."
        />
        <p
          class="text-xs"
          :class="bodyError ? 'text-n-ruby-11' : 'text-n-slate-10'"
        >
          {{ state.bodyText.length }}/1024 caracteres
        </p>
      </div>

      <!-- Footer -->
      <Input
        v-model="state.footerText"
        label="Rodapé (opcional)"
        placeholder="Ex: Responda SAIR para cancelar"
      />

      <!-- Buttons -->
      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <label class="text-sm font-medium text-n-slate-12">
            Botões (opcional)
          </label>
          <Button
            v-if="state.buttons.length < 3"
            icon="i-lucide-plus"
            size="xs"
            color="slate"
            variant="faded"
            label="Adicionar"
            @click="addButton"
          />
        </div>
        <div
          v-for="(button, index) in state.buttons"
          :key="index"
          class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak bg-n-alpha-1"
        >
          <div class="flex items-center gap-2">
            <ComboBox
              v-model="button.type"
              :options="BUTTON_TYPES"
              class="flex-1"
            />
            <Button
              icon="i-lucide-trash-2"
              size="xs"
              color="ruby"
              variant="faded"
              @click="removeButton(index)"
            />
          </div>
          <Input
            v-model="button.text"
            placeholder="Texto do botão"
          />
          <Input
            v-if="button.type === 'URL'"
            v-model="button.url"
            placeholder="https://exemplo.com/{{1}}"
          />
          <Input
            v-if="button.type === 'PHONE_NUMBER'"
            v-model="button.phoneNumber"
            placeholder="+5511999999999"
          />
        </div>
      </div>
    </form>

    <template #footer>
      <div class="flex gap-3 w-full">
        <Button
          class="w-full"
          :label="t('WHATSAPP_TEMPLATE_MGMT.CREATE.SUBMIT')"
          :is-loading="isSubmitting"
          :disabled="!isFormValid || isSubmitting"
          @click="handleSubmit"
        />
      </div>
    </template>
  </SidePanel>
</template>
