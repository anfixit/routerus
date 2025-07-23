import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { Toaster } from "react-hot-toast";

import App from "./App";
import "./index.css";

// Error boundary component
class ErrorBoundary extends React.Component<
  { children: React.ReactNode },
  { hasError: boolean; error?: Error }
> {
  constructor(props: { children: React.ReactNode }) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error("Application error:", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen bg-gradient-to-br from-red-50 to-red-100 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-xl p-8 max-w-md w-full text-center">
            <div className="text-6xl mb-4">💥</div>
            <h1 className="text-2xl font-bold text-gray-900 mb-4">
              Произошла ошибка
            </h1>
            <p className="text-gray-600 mb-6">
              Приложение столкнулось с неожиданной ошибкой. Попробуйте обновить
              страницу.
            </p>
            <div className="space-y-3">
              <button
                onClick={() => window.location.reload()}
                className="w-full bg-primary-600 text-white py-2 px-4 rounded-lg hover:bg-primary-700 transition-colors"
              >
                Обновить страницу
              </button>
              <details className="text-left">
                <summary className="cursor-pointer text-sm text-gray-500 hover:text-gray-700">
                  Показать детали ошибки
                </summary>
                <pre className="mt-2 text-xs bg-gray-100 p-2 rounded overflow-auto">
                  {this.state.error?.toString()}
                </pre>
              </details>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

// Toast configuration
const toastOptions = {
  duration: 4000,
  position: "top-right" as const,
  style: {
    borderRadius: "12px",
    background: "#363636",
    color: "#fff",
    boxShadow: "0 10px 25px -5px rgba(0, 0, 0, 0.25)",
  },
  success: {
    iconTheme: {
      primary: "#22c55e",
      secondary: "#fff",
    },
  },
  error: {
    iconTheme: {
      primary: "#ef4444",
      secondary: "#fff",
    },
  },
};

// App initialization
const initializeApp = () => {
  const root = ReactDOM.createRoot(
    document.getElementById("root") as HTMLElement,
  );

  root.render(
    <React.StrictMode>
      <ErrorBoundary>
        <BrowserRouter>
          <App />
          <Toaster
            toastOptions={toastOptions}
            containerStyle={{
              top: 20,
              right: 20,
            }}
          />
        </BrowserRouter>
      </ErrorBoundary>
    </React.StrictMode>,
  );

  // Remove loading class from body
  setTimeout(() => {
    document.body.classList.remove("loading");
  }, 100);
};

// Initialize app when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initializeApp);
} else {
  initializeApp();
}

// Performance monitoring (development only)
if (import.meta.env.DEV) {
  // Log performance metrics
  window.addEventListener("load", () => {
    setTimeout(() => {
      const perfData = performance.getEntriesByType(
        "navigation",
      )[0] as PerformanceNavigationTiming;
      console.group("🚀 Performance Metrics");
      console.log(
        `DOM Content Loaded: ${Math.round(perfData.domContentLoadedEventEnd - perfData.domContentLoadedEventStart)}ms`,
      );
      console.log(
        `Load Complete: ${Math.round(perfData.loadEventEnd - perfData.loadEventStart)}ms`,
      );
      console.log(
        `Total Load Time: ${Math.round(perfData.loadEventEnd - perfData.fetchStart)}ms`,
      );
      console.groupEnd();
    }, 1000);
  });

  // Log bundle size
  console.log(`🎯 App version: ${__APP_VERSION__ || "development"}`);
}

// Service worker registration (production only)
if (import.meta.env.PROD && "serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker
      .register("/sw.js")
      .then((registration) => {
        console.log("SW registered: ", registration);
      })
      .catch((registrationError) => {
        console.log("SW registration failed: ", registrationError);
      });
  });
}
