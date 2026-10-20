import { SDK_CSS } from './sdk.js';
import { IFrameHelper } from './IFrameHelper';
import { isExcludedURL, resolveBubbleVisibility } from './excludedPaths';
import { SDK_SET_BUBBLE_VISIBILITY } from 'shared/constants/sharedFrameEvents';

export const loadCSS = () => {
  const css = document.createElement('style');
  css.innerHTML = `${SDK_CSS}`;
  css.id = 'cw-widget-styles';
  css.dataset.turboPermanent = true;
  document.body.appendChild(css);
};

// This is a method specific to Turbo
// The body replacing strategy removes Chatwoot styles
// as well as the widget, this help us get it back
export const restoreElement = (id, newBody) => {
  const element = document.getElementById(id);
  const newElement = newBody.querySelector(`#${id}`);

  if (element && !newElement) {
    newBody.appendChild(element);
  }
};

export const restoreWidgetInDOM = newBody => {
  restoreElement('cw-bubble-holder', newBody);
  restoreElement('cw-widget-holder', newBody);
  restoreElement('cw-widget-styles', newBody);
};

export const addClasses = (elm, classes) => {
  elm.classList.add(...classes.split(' '));
};

export const toggleClass = (elm, classes) => {
  elm.classList.toggle(classes);
};

export const removeClasses = (elm, classes) => {
  elm.classList.remove(...classes.split(' '));
};

export const onLocationChange = ({ referrerURL, referrerHost }) => {
  IFrameHelper.events.onLocationChange({
    referrerURL,
    referrerHost,
  });
};

export const applyBubbleVisibility = visibility => {
  const widgetElm = document.querySelector('.woot--bubble-holder');
  const widgetHolder = document.querySelector('.woot-widget-holder');
  if (visibility === 'hide') {
    addClasses(widgetHolder, 'woot-widget--without-bubble');
    addClasses(widgetElm, 'woot-hidden');
    window.$chatwoot.hideMessageBubble = true;
  } else if (visibility === 'show') {
    removeClasses(widgetElm, 'woot-hidden');
    removeClasses(widgetHolder, 'woot-widget--without-bubble');
    window.$chatwoot.hideMessageBubble = false;
  }
  IFrameHelper.sendMessage(SDK_SET_BUBBLE_VISIBILITY, {
    hideMessageBubble: window.$chatwoot.hideMessageBubble,
  });
};

export const isCurrentURLExcluded = () =>
  isExcludedURL(window.$chatwoot?.excludedPaths, window.location.href);

const checkExcludedPaths = () => {
  if (!window.$chatwoot) return;
  const excluded = isCurrentURLExcluded();
  if (excluded === window.$chatwoot._hiddenByExclusion) return;

  window.$chatwoot._hiddenByExclusion = excluded;
  applyBubbleVisibility(
    resolveBubbleVisibility({
      requested: window.$chatwoot._requestedBubbleVisibility,
      excluded,
    })
  );
};

export const onLocationChangeListener = () => {
  let oldHref = document.location.href;
  const referrerHost = document.location.host;
  const config = {
    childList: true,
    subtree: true,
  };
  onLocationChange({
    referrerURL: oldHref,
    referrerHost,
  });
  checkExcludedPaths();

  const bodyList = document.querySelector('body');
  const observer = new MutationObserver(mutations => {
    mutations.forEach(() => {
      if (oldHref !== document.location.href) {
        oldHref = document.location.href;
        onLocationChange({
          referrerURL: oldHref,
          referrerHost,
        });
        checkExcludedPaths();
      }
    });
  });

  observer.observe(bodyList, config);
};
