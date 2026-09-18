import { build } from 'esbuild';
import { readFile, writeFile, mkdir, readdir, copyFile, chmod } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const app = resolve(process.argv[2]);
const resources = join(app, 'Contents/Resources');
await mkdir(join(resources, 'collector'), {recursive:true});
await mkdir(join(resources, 'feeds'), {recursive:true});
await mkdir(join(app, 'Contents/Helpers'), {recursive:true});
const bundle = await build({entryPoints:['src/desktop-collector.ts'],bundle:true,platform:'node',target:'node22',format:'esm',
  outfile:join(resources,'collector/desktop.mjs'),metafile:true,legalComments:'eof',
  banner:{js:"import {createRequire as __createRequire} from 'node:module'; const require=__createRequire(import.meta.url);"}});
await copyFile('feeds/direct-feeds.json',join(resources,'feeds/direct-feeds.json'));

// Pin and verify the official runtime so a downloaded app works without installing Node.
const version='22.23.2';
const filename=`node-v${version}-darwin-arm64.tar.gz`;
const expected='61130f394c1630d211dd50aecc4353d379480f36d3ac913cd85dbba1aed585c6';
const cache=resolve('.build/runtime'); await mkdir(cache,{recursive:true});
const archive=join(cache,filename);
let bytes;
try {bytes=await readFile(archive);} catch {
  const response=await fetch(`https://nodejs.org/dist/v${version}/${filename}`,{signal:AbortSignal.timeout(120_000)});
  if(!response.ok)throw new Error(`Node download: HTTP ${response.status}`);
  bytes=Buffer.from(await response.arrayBuffer());await writeFile(archive,bytes);
}
if(createHash('sha256').update(bytes).digest('hex')!==expected)throw new Error('Node runtime checksum mismatch');
execFileSync('tar',['-xzf',archive,'-C',cache,`node-v${version}-darwin-arm64/bin/node`,`node-v${version}-darwin-arm64/LICENSE`]);
await copyFile(join(cache,`node-v${version}-darwin-arm64/bin/node`),join(app,'Contents/Helpers/node'));
await chmod(join(app,'Contents/Helpers/node'),0o755);
await copyFile(join(cache,`node-v${version}-darwin-arm64/LICENSE`),join(resources,'NODE-LICENSE.txt'));

const roots=new Set();
for(const input of Object.keys(bundle.metafile.inputs)) {
  if(!input.includes('node_modules/'))continue;
  let directory=dirname(resolve(input));
  while(directory!==dirname(directory)) {
    try { const pkg=JSON.parse(await readFile(join(directory,'package.json'),'utf8')); if(pkg.name){roots.add(directory);break;} } catch {}
    directory=dirname(directory);
  }
}
let notices='# Bundled collector dependency notices\n\nThe Node.js runtime and its dependencies are licensed separately in NODE-LICENSE.txt.\n';
for(const root of [...roots].sort()) {
  const pkg=JSON.parse(await readFile(join(root,'package.json'),'utf8'));
  const files=(await readdir(root)).filter(name=>/^(licen[sc]e|copying)([._-]|$)/i.test(name));
  notices+=`\n## ${pkg.name}@${pkg.version}\n\n`;
  if(!files.length) {
    if(pkg.name!=='boolbase' || pkg.license!=='ISC')throw new Error(`Missing license text for bundled dependency ${pkg.name}`);
    notices+=`The published boolbase package declares the ISC license and names ${pkg.author} as its author. It includes no separate license file.\n\nISC License\n\nCopyright (c) Felix Boehm\n\nPermission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.\n\nTHE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.\n`;
  }
  for(const file of files)notices+=await readFile(join(root,file),'utf8')+'\n';
}
await writeFile(join(resources,'COLLECTOR-THIRD-PARTY-NOTICES.txt'),notices);
console.log(`Bundled collector and verified Node ${version}; ${roots.size} dependency notices.`);
