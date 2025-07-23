// API Types
export interface ApiResponse<T = any> {
  data: T;
  message?: string;
  status: "success" | "error";
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  pages: number;
  limit: number;
}

// Auth Types
export interface User {
  id: number;
  username: string;
  email: string;
  full_name?: string;
  is_active: boolean;
  is_superuser: boolean;
  last_login?: string;
  created_at: string;
}

export interface LoginRequest {
  username: string;
  password: string;
}

export interface LoginResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
  user: User;
}

export interface AuthState {
  user: User | null;
  token: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
}

// Server Types
export enum ServerStatus {
  ONLINE = "online",
  OFFLINE = "offline",
  UNKNOWN = "unknown",
  MAINTENANCE = "maintenance",
}

export interface Server {
  id: number;
  name: string;
  ip: string;
  port: number;
  location: string;
  country_code?: string;
  status: ServerStatus;
  last_check: string;
  uptime: number;
  total_users: number;
  active_users: number;
  total_traffic_gb: number;
  max_users: number;
  max_traffic_gb: number;
  reality_public_key?: string;
  description?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface ServerCreate {
  name: string;
  ip: string;
  port?: number;
  location: string;
  country_code?: string;
  description?: string;
  max_users?: number;
  max_traffic_gb?: number;
  reality_dest?: string;
  reality_server_name?: string;
}

export interface ServerUpdate {
  name?: string;
  location?: string;
  description?: string;
  max_users?: number;
  max_traffic_gb?: number;
  is_active?: boolean;
}

export interface ServerStats {
  cpu_usage: number;
  memory_usage: number;
  disk_usage: number;
  network_in: number;
  network_out: number;
  active_connections: number;
  total_connections: number;
  timestamp: string;
}

export interface ServerMetrics {
  server_id: number;
  server_name: string;
  server_ip: string;
  status: ServerStatus;
  cpu_usage: number;
  memory_usage: number;
  disk_usage: number;
  active_connections: number;
  total_users: number;
  active_users: number;
  uptime: number;
  last_check: string;
}

// User Types
export enum UserStatus {
  ACTIVE = "active",
  INACTIVE = "inactive",
  SUSPENDED = "suspended",
  EXPIRED = "expired",
}

export interface VpnUser {
  id: number;
  email: string;
  name?: string;
  vpn_uuid: string;
  server_id: number;
  status: UserStatus;
  traffic_limit_gb: number;
  used_traffic_gb: number;
  max_connections: number;
  current_connections: number;
  total_traffic_gb: number;
  last_connection?: string;
  connection_count: number;
  expires_at?: string;
  config_url?: string;
  notes?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface VpnUserCreate {
  email: string;
  name?: string;
  server_id: number;
  traffic_limit_gb?: number;
  max_connections?: number;
  expires_at?: string;
  notes?: string;
}

export interface VpnUserUpdate {
  name?: string;
  status?: UserStatus;
  traffic_limit_gb?: number;
  max_connections?: number;
  expires_at?: string;
  notes?: string;
  is_active?: boolean;
}

export interface VpnUserConfig {
  vpn_uuid: string;
  config_url: string;
  qr_code: string;
  server_ip: string;
  server_name: string;
}

export interface UserConnection {
  id: number;
  ip_address?: string;
  user_agent?: string;
  country?: string;
  bytes_sent: number;
  bytes_received: number;
  connected_at: string;
  disconnected_at?: string;
  duration_seconds: number;
}

// Dashboard Types
export interface DashboardStats {
  total_servers: number;
  online_servers: number;
  offline_servers: number;
  total_users: number;
  active_users: number;
  suspended_users: number;
  total_traffic_gb: number;
  servers_load: Record<string, number>;
}

export interface SystemStats {
  cpu_usage: number;
  memory_usage: number;
  disk_usage: number;
  network_in: number;
  network_out: number;
  uptime: number;
  load_average: number[];
}

export interface TrafficStats {
  period: string;
  total_gb: number;
  upload_gb: number;
  download_gb: number;
  timestamp: string;
}

export interface Alert {
  type: "error" | "warning" | "info" | "success";
  message: string;
  timestamp: string;
  server_id?: number;
}

// Chart Types
export interface ChartDataPoint {
  timestamp: string;
  value: number;
  label?: string;
}

export interface ChartData {
  labels: string[];
  datasets: {
    label: string;
    data: number[];
    borderColor?: string;
    backgroundColor?: string;
    fill?: boolean;
  }[];
}

// UI Types
export interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title?: string;
  children: React.ReactNode;
}

export interface TableColumn<T> {
  key: keyof T | string;
  title: string;
  render?: (value: any, record: T) => React.ReactNode;
  sortable?: boolean;
  width?: string;
  align?: "left" | "center" | "right";
}

export interface TableProps<T> {
  data: T[];
  columns: TableColumn<T>[];
  loading?: boolean;
  pagination?: {
    current: number;
    total: number;
    pageSize: number;
    onChange: (page: number) => void;
  };
  onRowClick?: (record: T) => void;
}

export interface FilterOptions {
  search?: string;
  status?: string;
  server_id?: number;
  sort_by?: string;
  sort_order?: "asc" | "desc";
  page?: number;
  limit?: number;
}

// Store Types
export interface AppState {
  auth: AuthState;
  servers: {
    list: Server[];
    current: Server | null;
    loading: boolean;
    error: string | null;
  };
  users: {
    list: VpnUser[];
    current: VpnUser | null;
    loading: boolean;
    error: string | null;
  };
  dashboard: {
    stats: DashboardStats | null;
    systemStats: SystemStats | null;
    alerts: Alert[];
    loading: boolean;
  };
  ui: {
    sidebarCollapsed: boolean;
    theme: "light" | "dark";
    language: string;
  };
}

// Form Types
export interface FormField {
  name: string;
  type:
    | "text"
    | "email"
    | "password"
    | "number"
    | "select"
    | "textarea"
    | "checkbox"
    | "date";
  label: string;
  placeholder?: string;
  required?: boolean;
  validation?: any;
  options?: { value: string | number; label: string }[];
}

export interface FormConfig {
  fields: FormField[];
  onSubmit: (data: any) => void;
  loading?: boolean;
  initialValues?: any;
}

// Deployment Types
export interface DeployCommand {
  server_id: number;
  server_ip: string;
  deploy_command: string;
  instructions: string[];
  environment_variables: Record<string, string>;
}

// Monitoring Types
export interface MonitoringConfig {
  prometheus_url: string;
  grafana_url: string;
  alert_rules: AlertRule[];
}

export interface AlertRule {
  name: string;
  condition: string;
  threshold: number;
  duration: string;
  severity: "low" | "medium" | "high" | "critical";
}

// Export all types as a namespace for easier imports
export * from "./api";
export * from "./auth";
export * from "./server";
export * from "./user";

// Utility types
export type LoadingState = "idle" | "loading" | "success" | "error";

export type SortOrder = "asc" | "desc";

export type Theme = "light" | "dark" | "system";

export type Language = "en" | "ru";
