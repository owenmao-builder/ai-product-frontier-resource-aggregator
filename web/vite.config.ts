import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  base: process.env.MAC_APP ? './' : process.env.GITHUB_PAGES ? '/ai-product-frontier-resource-aggregator/' : '/',
  server: {
    port: 3000,
    open: true,
    fs: {
      allow: ['..']
    }
  },
  publicDir: path.resolve(__dirname, '../'),
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    copyPublicDir: false,
    ...(process.env.MAC_APP ? { rollupOptions: { output: { format: 'iife' as const, inlineDynamicImports: true } } } : {}),
  },
})
