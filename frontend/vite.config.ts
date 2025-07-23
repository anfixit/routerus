import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "path";

export default defineConfig({
  plugins: [react()],

  // Разрешение путей
  resolve: {
    alias: {
      "@": resolve(__dirname, "./src"),
      "@components": resolve(__dirname, "./src/components"),
      "@pages": resolve(__dirname, "./src/pages"),
      "@hooks": resolve(__dirname, "./src/hooks"),
      "@utils": resolve(__dirname, "./src/utils"),
      "@types": resolve(__dirname, "./src/types"),
    },
  },

  // Сервер разработки
  server: {
    host: "0.0.0.0",
    port: 3000,
    proxy: {
      "/api": {
        target: "http://localhost:8000",
        changeOrigin: true,
        secure: false,
      },
    },
  },

  // Настройки сборки
  build: {
    outDir: "dist",
    sourcemap: false,
    minify: "terser",
    target: "es2020",
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ["react", "react-dom", "react-router-dom"],
          ui: ["framer-motion", "lucide-react", "react-hot-toast"],
          charts: ["recharts"],
          utils: ["axios", "date-fns", "zustand"],
        },
      },
    },
  },

  // Оптимизация
  optimizeDeps: {
    include: ["react", "react-dom", "react-router-dom"],
  },

  // Переменные окружения
  define: {
    __APP_VERSION__: JSON.stringify(process.env.npm_package_version),
  },
});
