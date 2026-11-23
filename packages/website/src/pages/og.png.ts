import type { APIRoute } from 'astro';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { render } from 'takumi-js';
import { fontFiles } from '../../fonts.mjs';
import template from '../../og-image/og.html?raw';
import stylesheet from '../../og-image/base.css?raw';
import favicon from '../../public/favicon.svg?raw';

const fontData = (specifier: string) => readFile(fileURLToPath(import.meta.resolve(specifier)));

// og-image/og.html also opens in a browser for editing; inline its stylesheet and favicon here.
const html = template
  .replace('<link rel="stylesheet" href="base.css">', `<style>${stylesheet}</style>`)
  .replace('src="../public/favicon.svg"', `src="data:image/svg+xml;base64,${Buffer.from(favicon).toString('base64')}"`);

export const GET: APIRoute = async () => {
  const png = await render(html, {
    width: 1200,
    height: 630,
    format: 'png',
    fonts: [
      { name: 'Geist', data: await fontData(fontFiles.sans) },
      { name: 'Geist Mono', data: await fontData(fontFiles.mono) },
    ],
  });
  return new Response(new Uint8Array(png), { headers: { 'Content-Type': 'image/png' } });
};
