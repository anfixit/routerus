import axios from 'axios';

const API_URL = '/api/v1';

// Функция для выполнения запросов с авторизацией
const authRequest = async (method, url, data = null) => {
  const token = localStorage.getItem('token');
  
  try {
    const response = await axios({
      method,
      url: `${API_URL}${url}`,
      data,
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });
    return response.data;
  } catch (error) {
    throw new Error(error.response?.data?.detail || 'Ошибка запроса');
  }
};

export const getConfigs = async () => {
  return authRequest('get', '/configs/');
};

export const createWireguardConfig = async (data) => {
  return authRequest('post', '/configs/wireguard', data);
};

export const createShadowsocksConfig = async (data) => {
  return authRequest('post', '/configs/shadowsocks', data);
};

export const createXrayConfig = async (data) => {
  return authRequest('post', '/configs/xray', data);
};

export const getConfig = async (configId) => {
  return authRequest('get', `/configs/${configId}`);
};

export const updateConfig = async (configId, data) => {
  return authRequest('put', `/configs/${configId}`, data);
};

export const deleteConfig = async (configId) => {
  return authRequest('delete', `/configs/${configId}`);
};
