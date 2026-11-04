import { onBeforeUnmount, ref } from 'vue';

// Relógio compartilhado (segundos Unix) que avança a cada minuto: um só
// intervalo para todos os cartões da lista, enquanto houver alguém usando.
const now = ref(Math.floor(Date.now() / 1000));
let users = 0;
let timer = null;

export const useMinuteClock = () => {
  users += 1;
  if (!timer) {
    now.value = Math.floor(Date.now() / 1000);
    timer = setInterval(() => {
      now.value = Math.floor(Date.now() / 1000);
    }, 60000);
  }

  onBeforeUnmount(() => {
    users -= 1;
    if (users === 0 && timer) {
      clearInterval(timer);
      timer = null;
    }
  });

  return now;
};
