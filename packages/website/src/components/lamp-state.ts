export function syncLampLinks() {
  const lampOff = document.documentElement.dataset.lamp === 'off';

  for (const link of document.querySelectorAll<HTMLAnchorElement>('a[data-lamp-link]')) {
    const url = new URL(link.href);
    if (lampOff) url.searchParams.set('lamp', 'off');
    else url.searchParams.delete('lamp');
    link.href = url.href;
  }
}

export function setLamp(lit: boolean) {
  const url = new URL(window.location.href);
  if (lit) {
    url.searchParams.delete('lamp');
    delete document.documentElement.dataset.lamp;
  } else {
    url.searchParams.set('lamp', 'off');
    document.documentElement.dataset.lamp = 'off';
  }
  history.replaceState(history.state, '', url);
  syncLampLinks();
}
