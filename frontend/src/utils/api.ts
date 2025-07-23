import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from "axios";
import toast from "react-hot-toast";

import type {
  ApiResponse,
  LoginRequest,
  LoginResponse,
  Server,
  ServerCreate,
  ServerUpdate,
  VpnUser,
  VpnUserCreate,
  VpnUserUpdate,
  VpnUserConfig,
  DashboardStats,
  SystemStats,
  ServerMetrics,
  TrafficStats,
  Alert,
} from "@/types";

// API configuration
const API_BASE_URL = import.meta.env.VITE_API_URL || "/api";
const API_TIMEOUT = 30000;

// Create axios instance
const api: AxiosInstance = axios.create({
  baseURL: API_BASE_URL,
  timeout: API_TIMEOUT,
  headers: {
    "Content-Type": "application/json",
  },
});

// Request interceptor
api.interceptors.request.use(
  (config) => {
    // Add auth token if available
    const token = localStorage.getItem("auth_token");
    if (token && config.headers) {
      config.headers.Authorization = `Bearer ${token}`;
    }

    // Add request timestamp for debugging
    if (import.meta.env.DEV) {
      console.log(
        `🚀 API Request: ${config.method?.toUpperCase()} ${config.url}`,
        {
          data: config.data,
          params: config.params,
        },
      );
    }

    return config;
  },
  (error) => {
    console.error("❌ Request error:", error);
    return Promise.reject(error);
  },
);

// Response interceptor
api.interceptors.response.use(
  (response: AxiosResponse) => {
    if (import.meta.env.DEV) {
      console.log(
        `✅ API Response: ${response.config.method?.toUpperCase()} ${response.config.url}`,
        {
          status: response.status,
          data: response.data,
        },
      );
    }
    return response;
  },
  (error) => {
    const message =
      error.response?.data?.detail || error.message || "Произошла ошибка";

    // Handle different error types
    if (error.response?.status === 401) {
      // Unauthorized - clear auth and redirect to login
      localStorage.removeItem("auth_token");
      localStorage.removeItem("auth_user");
      window.location.href = "/login";
      return Promise.reject(error);
    }

    if (error.response?.status === 403) {
      toast.error("Недостаточно прав доступа");
    } else if (error.response?.status === 404) {
      toast.error("Ресурс не найден");
    } else if (error.response?.status >= 500) {
      toast.error("Ошибка сервера. Попробуйте позже");
    } else if (error.code === "ECONNABORTED") {
      toast.error("Превышено время ожидания запроса");
    } else if (!error.response) {
      toast.error("Нет соединения с сервером");
    } else {
      toast.error(message);
    }

    console.error("❌ API Error:", {
      status: error.response?.status,
      message,
      url: error.config?.url,
      method: error.config?.method,
    });

    return Promise.reject(error);
  },
);

// Generic API methods
class ApiClient {
  // Auth methods
  async login(credentials: LoginRequest): Promise<LoginResponse> {
    const response = await api.post<LoginResponse>("/auth/login", credentials);
    return response.data;
  }

  async logout(): Promise<void> {
    await api.post("/auth/logout");
    localStorage.removeItem("auth_token");
    localStorage.removeItem("auth_user");
  }

  async refreshToken(): Promise<{ access_token: string }> {
    const response = await api.post<{ access_token: string }>("/auth/refresh");
    return response.data;
  }

  async getMe(): Promise<any> {
    const response = await api.get("/auth/me");
    return response.data;
  }

  // Server methods
  async getServers(): Promise<Server[]> {
    const response = await api.get<Server[]>("/servers/");
    return response.data;
  }

  async getServer(id: number): Promise<Server> {
    const response = await api.get<Server>(`/servers/${id}`);
    return response.data;
  }

  async createServer(data: ServerCreate): Promise<Server> {
    const response = await api.post<Server>("/servers/", data);
    return response.data;
  }

  async updateServer(id: number, data: ServerUpdate): Promise<Server> {
    const response = await api.put<Server>(`/servers/${id}`, data);
    return response.data;
  }

  async deleteServer(id: number): Promise<void> {
    await api.delete(`/servers/${id}`);
  }

  async checkServerStatus(
    id: number,
  ): Promise<{ status: string; checked_at: string }> {
    const response = await api.post(`/servers/${id}/check-status`);
    return response.data;
  }

  async getServerStats(id: number, hours: number = 24): Promise<any[]> {
    const response = await api.get(`/servers/${id}/stats`, {
      params: { hours },
    });
    return response.data;
  }

  async getDeployCommand(id: number): Promise<any> {
    const response = await api.post(`/servers/${id}/deploy`);
    return response.data;
  }

  async updateServerConfig(id: number): Promise<void> {
    await api.post(`/servers/${id}/update-config`);
  }

  // User methods
  async getUsers(params?: any): Promise<VpnUser[]> {
    const response = await api.get<VpnUser[]>("/users/", { params });
    return response.data;
  }

  async getUser(id: number): Promise<VpnUser> {
    const response = await api.get<VpnUser>(`/users/${id}`);
    return response.data;
  }

  async createUser(data: VpnUserCreate): Promise<VpnUser> {
    const response = await api.post<VpnUser>("/users/", data);
    return response.data;
  }

  async updateUser(id: number, data: VpnUserUpdate): Promise<VpnUser> {
    const response = await api.put<VpnUser>(`/users/${id}`, data);
    return response.data;
  }

  async deleteUser(id: number): Promise<void> {
    await api.delete(`/users/${id}`);
  }

  async getUserConfig(id: number): Promise<VpnUserConfig> {
    const response = await api.get<VpnUserConfig>(`/users/${id}/config`);
    return response.data;
  }

  async regenerateUserConfig(
    id: number,
  ): Promise<{ message: string; new_uuid: string }> {
    const response = await api.post(`/users/${id}/regenerate-config`);
    return response.data;
  }

  async getUserConnections(id: number, limit: number = 50): Promise<any[]> {
    const response = await api.get(`/users/${id}/connections`, {
      params: { limit },
    });
    return response.data;
  }

  async suspendUser(id: number): Promise<void> {
    await api.post(`/users/${id}/suspend`);
  }

  async activateUser(id: number): Promise<void> {
    await api.post(`/users/${id}/activate`);
  }

  // Monitoring methods
  async getDashboardStats(): Promise<DashboardStats> {
    const response = await api.get<DashboardStats>("/monitoring/dashboard");
    return response.data;
  }

  async getSystemStats(): Promise<SystemStats> {
    const response = await api.get<SystemStats>("/monitoring/system");
    return response.data;
  }

  async getServersMetrics(): Promise<ServerMetrics[]> {
    const response = await api.get<ServerMetrics[]>("/monitoring/servers");
    return response.data;
  }

  async getTrafficStats(
    period: string = "24h",
    serverId?: number,
  ): Promise<TrafficStats[]> {
    const params: any = { period };
    if (serverId) params.server_id = serverId;

    const response = await api.get<TrafficStats[]>("/monitoring/traffic", {
      params,
    });
    return response.data;
  }

  async getAlerts(): Promise<{ alerts: Alert[] }> {
    const response = await api.get("/monitoring/alerts");
    return response.data;
  }

  async collectStats(): Promise<any> {
    const response = await api.post("/monitoring/collect-stats");
    return response.data;
  }

  async getPrometheusMetrics(): Promise<string> {
    const response = await api.get("/monitoring/prometheus", {
      headers: { Accept: "text/plain" },
    });
    return response.data;
  }

  // Utility methods
  async healthCheck(): Promise<any> {
    const response = await api.get("/health");
    return response.data;
  }

  async getApiInfo(): Promise<any> {
    const response = await api.get("/info");
    return response.data;
  }
}

// Create and export API client instance
export const apiClient = new ApiClient();

// Export types and utilities
export { api };
export type { AxiosRequestConfig, AxiosResponse };

// Helper functions
export const setAuthToken = (token: string) => {
  localStorage.setItem("auth_token", token);
  api.defaults.headers.common["Authorization"] = `Bearer ${token}`;
};

export const removeAuthToken = () => {
  localStorage.removeItem("auth_token");
  delete api.defaults.headers.common["Authorization"];
};

export const getAuthToken = (): string | null => {
  return localStorage.getItem("auth_token");
};

// Request helpers
export const createFormData = (data: Record<string, any>): FormData => {
  const formData = new FormData();
  Object.entries(data).forEach(([key, value]) => {
    if (value !== null && value !== undefined) {
      formData.append(key, value);
    }
  });
  return formData;
};

export const downloadFile = async (
  url: string,
  filename: string,
): Promise<void> => {
  try {
    const response = await api.get(url, { responseType: "blob" });
    const blob = new Blob([response.data]);
    const downloadUrl = window.URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = downloadUrl;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.URL.revokeObjectURL(downloadUrl);
  } catch (error) {
    console.error("Download error:", error);
    throw error;
  }
};

// API status checker
export const checkApiStatus = async (): Promise<boolean> => {
  try {
    await apiClient.healthCheck();
    return true;
  } catch {
    return false;
  }
};
