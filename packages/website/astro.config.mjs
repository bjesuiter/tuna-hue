import { defineConfig } from 'astro/config';

export default defineConfig({
  output: 'static',
  site: 'https://bjesuiter.github.io',
  base: '/tuna-hue',
  build: { inlineStylesheets: 'always' },
});
