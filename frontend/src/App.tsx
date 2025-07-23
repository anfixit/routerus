import React, { useEffect, useState } from "react";
import { Routes, Route, Navigate, useLocation } from "react-router-dom";
import { AnimatePresence } from "framer-motion";

import { useAuthStore } from "@/hooks/useAuthStore";
import { apiClient } from "@/utils/api";

// Layout components
import Layout from "@/components/Layout";
import LoadingScreen from "@/components/LoadingScreen";

// Pages
import LoginPage from "@/pages/Login";
import DashboardPage from "@/pages/Dashboard";
import ServersPage from "@/pages/Servers";
import UsersPage from "@/pages/Users";
import MonitoringPage from "@/pages/Monitoring";
import SettingsPage from "@/pages/Settings";
import NotFoundPage from "@/pages/NotFound";

// Protected Route Component
interface ProtectedRouteProps {
  children: React.ReactNode;
}

const ProtectedRoute: React.FC<ProtectedRouteProps> = ({ children }) => {
  const { isAuthenticated, isLoading } = useAuthStore();

  if (isLoading) {
    return <LoadingScreen />;
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return <>{children}</>;
};

// Public Route Component (redirects if authenticated)
const PublicRoute: React.FC<ProtectedRouteProps> = ({ children }) => {
  const { isAuthenticated, isLoading } = useAuthStore();

  if (isLoading) {
    return <LoadingScreen />;
  }

  if (isAuthenticated) {
    return <Navigate to="/dashboard" replace />;
  }

  return <>{children}</>;
};

// Main App Component
const App: React.FC = () => {
  const location = useLocation();
  const { initializeAuth, isLoading, isAuthenticated } = useAuthStore();
  const [appReady, setAppReady] = useState(false);

  // Initialize app
  useEffect(() => {
    const initApp = async () => {
      try {
        // Check API health
        await apiClient.healthCheck();

        // Initialize authentication
        await initializeAuth();

        // App is ready
        setAppReady(true);
      } catch (error) {
        console.error("App initialization failed:", error);
        // Still set app as ready to show error state
        setAppReady(true);
      }
    };

    initApp();
  }, [initializeAuth]);

  // Show loading screen while app initializes
  if (!appReady || isLoading) {
    return <LoadingScreen />;
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <AnimatePresence mode="wait" initial={false}>
        <Routes location={location} key={location.pathname}>
          {/* Public Routes */}
          <Route
            path="/login"
            element={
              <PublicRoute>
                <LoginPage />
              </PublicRoute>
            }
          />

          {/* Protected Routes */}
          <Route
            path="/"
            element={
              <ProtectedRoute>
                <Layout />
              </ProtectedRoute>
            }
          >
            {/* Dashboard */}
            <Route index element={<Navigate to="/dashboard" replace />} />
            <Route path="dashboard" element={<DashboardPage />} />

            {/* Servers */}
            <Route path="servers" element={<ServersPage />} />
            <Route path="servers/:id" element={<ServersPage />} />

            {/* Users */}
            <Route path="users" element={<UsersPage />} />
            <Route path="users/:id" element={<UsersPage />} />

            {/* Monitoring */}
            <Route path="monitoring" element={<MonitoringPage />} />

            {/* Settings */}
            <Route path="settings" element={<SettingsPage />} />
          </Route>

          {/* 404 Page */}
          <Route path="*" element={<NotFoundPage />} />
        </Routes>
      </AnimatePresence>

      {/* Global App Components */}
      <AppGlobalComponents />
    </div>
  );
};

// Global components that should be rendered on every page
const AppGlobalComponents: React.FC = () => {
  const { isAuthenticated } = useAuthStore();

  return (
    <>
      {/* Connection Status Indicator */}
      <ConnectionStatus />

      {/* Real-time Notifications (only when authenticated) */}
      {isAuthenticated && <RealtimeNotifications />}

      {/* Keyboard Shortcuts Handler */}
      <KeyboardShortcuts />
    </>
  );
};

// Connection Status Component
const ConnectionStatus: React.FC = () => {
  const [isOnline, setIsOnline] = useState(navigator.onLine);

  useEffect(() => {
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);

    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);

    return () => {
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
    };
  }, []);

  if (isOnline) return null;

  return (
    <div className="fixed bottom-4 left-4 z-50 bg-error-600 text-white px-4 py-2 rounded-lg shadow-lg animate-slide-up">
      <div className="flex items-center space-x-2">
        <div className="w-2 h-2 bg-white rounded-full animate-pulse" />
        <span className="text-sm font-medium">Нет подключения к интернету</span>
      </div>
    </div>
  );
};

// Real-time Notifications Component
const RealtimeNotifications: React.FC = () => {
  useEffect(() => {
    // TODO: Implement WebSocket connection for real-time notifications
    // This could include server status changes, new users, alerts, etc.

    const connectWebSocket = () => {
      // const ws = new WebSocket('ws://localhost:8000/ws')
      // ws.onmessage = (event) => {
      //   const data = JSON.parse(event.data)
      //   // Handle real-time updates
      // }
    };

    // connectWebSocket()
  }, []);

  return null;
};

// Keyboard Shortcuts Component
const KeyboardShortcuts: React.FC = () => {
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      // Global keyboard shortcuts
      if (event.ctrlKey || event.metaKey) {
        switch (event.key) {
          case "k":
            // TODO: Open search/command palette
            event.preventDefault();
            break;
          case "/":
            // TODO: Focus search
            event.preventDefault();
            break;
          default:
            break;
        }
      }

      // ESC key to close modals/overlays
      if (event.key === "Escape") {
        // TODO: Close any open modals
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, []);

  return null;
};

export default App;
