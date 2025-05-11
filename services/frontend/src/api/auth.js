import axios from 'axios';

const API_URL = '/api/v1';

export const login = async (username, password) => {
  const formData = new URLSearchParams();
  formData.append('username', username);
  formData.append('password', password);

  try {
    const response = await axios.post(`${API_URL}/auth/login/access-token`, formData, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    });
    return response.data;
  } catch (error) {
    throw new Error(error.response?.data?.detail || 'Ошибка авторизации');
  }
};

export const validateToken = async (token) => {
  try {
    const response = await axios.get(`${API_URL}/auth/login/test-token`, {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });
    return response.data;
  } catch (error) {
    throw new Error('Токен недействителен');
  }
};
