import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  base: process.env.GITHUB_ACTIONS === 'true' ? '/sim-manager/' : '/',
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      registerType: 'autoUpdate',
      manifest: {
        name: 'SIMVault',
        short_name: 'SIMVault',
        description: '全球手机卡收藏者的本地数字卡册',
        theme_color: '#5669df',
        background_color: '#f5f7fb',
        display: 'standalone',
        icons: [],
      },
    }),
  ],
})
