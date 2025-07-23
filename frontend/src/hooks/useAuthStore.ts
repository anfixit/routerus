import { create } from "zustand";
import { persist } from "zustand/middleware";
import React from "react";
import toast from "react-hot-toast";

import type { User, LoginRequest, AuthState } from "@/types";
import {
  apiClient,
  setAuthToken,
  removeAuthToken,
  getAuthToken,
} from "@/utils/api";

interface AuthStore extends AuthState {
  // Actions
  login: (credentials: LoginRequest) => Promise<void>;
  logout: () => Promise<void>;
  initializeAuth: () => Promise<void>;
  refreshToken: () => Promise<void>;
  updateUser: (user: Partial<User>) => void;
  clearError: () => void;
}

export const useAuthStore = create<AuthStore>()(
  persist(
    (set, get) => ({
      // Initial state
      user: null,
      token: null,
      isAuthenticated: false,
      isLoading: false,

      // Login action
      login: async (credentials: LoginRequest) => {
        try {
          set({ isLoading: true });

          const response = await apiClient.login(credentials);

          // Set token in API client
          setAuthToken(response.access_token);

          // Update store
          set({
            user: response.user,
            token: response.access_token,
            isAuthenticated: true,
            isLoading: false,
          });

          toast.success(`Добро пожаловать, ${response.user.username}!`);
        } catch (error: any) {
          set({
            user: null,
            token: null,
            isAuthenticated: false,
            isLoading: false,
          });

          // Error is already handled in API interceptor
          throw error;
        }
      },

      // Logout action
      logout: async () => {
        try {
          // Call logout API
          await apiClient.logout();
        } catch (error) {
          // Continue with logout even if API call fails
          console.warn("Logout API call failed:", error);
        } finally {
          // Clear auth state
          removeAuthToken();
          set({
            user: null,
            token: null,
            isAuthenticated: false,
            isLoading: false,
          });

          toast.success("Вы успешно вышли из системы");
        }
      },

      // Initialize auth on app start
      initializeAuth: async () => {
        try {
          set({ isLoading: true });

          const token = getAuthToken();

          if (!token) {
            set({ isLoading: false });
            return;
          }

          // Verify token by getting user info
          const user = await apiClient.getMe();

          // Set token in API client
          setAuthToken(token);

          // Update store
          set({
            user,
            token,
            isAuthenticated: true,
            isLoading: false,
          });
        } catch (error) {
          console.warn("Auth initialization failed:", error);

          // Clear invalid auth state
          removeAuthToken();
          set({
            user: null,
            token: null,
            isAuthenticated: false,
            isLoading: false,
          });
        }
      },

      // Refresh token
      refreshToken: async () => {
        try {
          const response = await apiClient.refreshToken();

          // Update token
          setAuthToken(response.access_token);
          set({ token: response.access_token });
        } catch (error) {
          console.error("Token refresh failed:", error);

          // Force logout on refresh failure
          get().logout();
          throw error;
        }
      },

      // Update user info
      updateUser: (userUpdates: Partial<User>) => {
        const currentUser = get().user;
        if (currentUser) {
          set({
            user: { ...currentUser, ...userUpdates },
          });
        }
      },

      // Clear error (if we add error state later)
      clearError: () => {
        // Reserved for future error handling
      },
    }),
    {
      name: "routerus-auth",
      partialize: (state) => ({
        // Only persist these fields
        user: state.user,
        token: state.token,
        isAuthenticated: state.isAuthenticated,
      }),
      onRehydrateStorage: () => (state) => {
        // Called when store is rehydrated from localStorage
        if (state?.token) {
          setAuthToken(state.token);
        }
      },
    },
  ),
);

// Auth hooks and utilities
export const useAuth = () => {
  const store = useAuthStore();

  return {
    // State
    user: store.user,
    isAuthenticated: store.isAuthenticated,
    isLoading: store.isLoading,

    // Actions
    login: store.login,
    logout: store.logout,

    // Computed values
    isAdmin: store.user?.is_superuser || false,
    userName: store.user?.full_name || store.user?.username || "Пользователь",
  };
};

// Check if user has specific permission
export const usePermissions = () => {
  const { user, isAuthenticated } = useAuth();

  return {
    canManageServers: isAuthenticated && user?.is_superuser,
    canManageUsers: isAuthenticated && user?.is_superuser,
    canViewMonitoring: isAuthenticated,
    canManageSettings: isAuthenticated && user?.is_superuser,

    // Helper to check any permission
    hasPermission: (permission: string): boolean => {
      if (!isAuthenticated || !user) return false;

      // Admin has all permissions
      if (user.is_superuser) return true;

      // Add more granular permission checks here
      switch (permission) {
        case "view:dashboard":
          return true;
        case "view:servers":
          return true;
        case "create:servers":
        case "update:servers":
        case "delete:servers":
          return user.is_superuser;
        case "view:users":
          return true;
        case "create:users":
        case "update:users":
        case "delete:users":
          return user.is_superuser;
        default:
          return false;
      }
    },
  };
};

// Auto token refresh hook
export const useTokenRefresh = () => {
  const refreshToken = useAuthStore((state) => state.refreshToken);
  const token = useAuthStore((state) => state.token);

  React.useEffect(() => {
    if (!token) return;

    // Decode token to check expiration
    try {
      const payload = JSON.parse(atob(token.split(".")[1]));
      const expirationTime = payload.exp * 1000; // Convert to milliseconds
      const currentTime = Date.now();
      const timeUntilExpiry = expirationTime - currentTime;

      // Refresh token 5 minutes before expiry
      const refreshTime = timeUntilExpiry - 5 * 60 * 1000;

      if (refreshTime > 0) {
        const timeoutId = setTimeout(() => {
          refreshToken().catch(console.error);
        }, refreshTime);

        return () => clearTimeout(timeoutId);
      }
    } catch (error) {
      console.error("Failed to decode token:", error);
    }
  }, [token, refreshToken]);
};

// Session timeout hook
export const useSessionTimeout = (timeoutMinutes: number = 30) => {
  const logout = useAuthStore((state) => state.logout);
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);

  React.useEffect(() => {
    if (!isAuthenticated) return;

    let timeoutId: NodeJS.Timeout;

    const resetTimeout = () => {
      clearTimeout(timeoutId);
      timeoutId = setTimeout(
        () => {
          toast.error("Сессия истекла. Пожалуйста, войдите снова.");
          logout();
        },
        timeoutMinutes * 60 * 1000,
      );
    };

    // Reset timeout on user activity
    const events = [
      "mousedown",
      "mousemove",
      "keypress",
      "scroll",
      "touchstart",
    ];

    const resetTimeoutHandler = () => resetTimeout();

    events.forEach((event) => {
      document.addEventListener(event, resetTimeoutHandler, true);
    });

    // Initial timeout
    resetTimeout();

    return () => {
      clearTimeout(timeoutId);
      events.forEach((event) => {
        document.removeEventListener(event, resetTimeoutHandler, true);
      });
    };
  }, [isAuthenticated, logout, timeoutMinutes]);
};
