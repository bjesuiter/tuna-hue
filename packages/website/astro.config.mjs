import { defineConfig } from 'astro/config';

export default defineConfig({
  output: 'static',
  site: 'https://bjesuiter.github.io',
  base: '/tuna-hue',
  build: { inlineStylesheets: 'always' },
  vite: {
    // Keep Microlighter's on-demand grammar imports resolvable in dev and static builds.
    optimizeDeps: { exclude: ['microlighter'] },
    build: {
      dynamicImportVarsOptions: {
        include: /\/microlighter\/dist\/grammar-dependencies\.js$/,
        exclude: [],
      },
    },
  },
});
