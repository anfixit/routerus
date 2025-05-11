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

export const getUsers = async () => {
  return authRequest('get', '/users/');
};

export const createUser = async (userData) => {
  return authRequest('post', '/users/', userData);
};

export const updateUser = async (userId, userData) => {
  return authRequest('put', `/users/${userId}`, userData);
};

export const deleteUser = async (userId) => {
  return authRequest('delete', `/users/${userId}`);
};

export const getCurrentUser = async () => {
  return authRequest('get', '/users/me');
};
