export {}
declare global {
  interface Window {
    __AI_NATIVE__?: boolean
    webkit?: { messageHandlers: { newsBridge: { postMessage: (message: { action: string; range?: string; url?: string; section?: 'news' | 'products' }) => void } } }
  }
}
