import sitemap from '@astrojs/sitemap';
import { defineConfig, fontProviders } from 'astro/config';
import { spawnSync } from 'node:child_process';
import { fontFiles } from './fonts.mjs';

const commit = spawnSync('git', ['rev-parse', '--verify', 'HEAD'], {
  cwd: new URL('.', import.meta.url),
  encoding: 'utf8',
  stdio: ['ignore', 'pipe', 'ignore'],
}).stdout?.trim();

export default defineConfig({
  output: 'static',
  site: 'https://bjesuiter.github.io',
  base: '/tuna-hue',
  build: { inlineStylesheets: 'always' },
  vite: {
    define: {
      'import.meta.env.BUILD_TIME': JSON.stringify(new Date().toISOString()),
      'import.meta.env.BUILD_COMMIT': JSON.stringify(commit ?? ''),
    },
  },
  integrations: [sitemap()],
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
