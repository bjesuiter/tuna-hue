import { defineConfig, fontProviders } from 'astro/config';
import { fontFiles } from './fonts.mjs';

export default defineConfig({
  output: 'static',
  site: 'https://bjesuiter.github.io',
  base: '/tuna-hue',
  build: { inlineStylesheets: 'always' },
  fonts: [
    {
      provider: fontProviders.local(),
      name: 'Geist',
      cssVariable: '--font-geist',
      fallbacks: ['system-ui', 'sans-serif'],
      options: { variants: [{ src: [fontFiles.sans], weight: '100 900', style: 'normal' }] },
    },
    {
      provider: fontProviders.local(),
      name: 'Geist Mono',
      cssVariable: '--font-geist-mono',
      fallbacks: ['ui-monospace', 'monospace'],
      options: { variants: [{ src: [fontFiles.mono], weight: '100 900', style: 'normal' }] },
    },
  ],
});
