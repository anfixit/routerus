/**
 * RouteRus - Основной JavaScript файл
 */

// Ждем полной загрузки DOM перед инициализацией
document.addEventListener('DOMContentLoaded', function() {
    // Элементы страницы
    const categorySelect = document.getElementById('categorySelect');
    const servicesList = document.getElementById('servicesList');
    const newCategoryInput = document.getElementById('newCategoryInput');
    const newServiceInput = document.getElementById('newServiceInput');
    const addServiceBtn = document.getElementById('addServiceBtn');
    const formatOptions = document.querySelectorAll('.format-option');
    const generateBtn = document.getElementById('generateBtn');
    const processingStatus = document.getElementById('processingStatus');
    const progressBar = document.getElementById('progressBar');
    const statusMessage = document.getElementById('statusMessage');
    const resultsSection = document.getElementById('resultsSection');
    const downloadLinks = document.getElementById('downloadLinks');
    const newGenerationBtn = document.getElementById('newGenerationBtn');

    // Модальное окно сообщений
    const messageModal = new bootstrap.Modal(document.getElementById('messageModal'));
    const messageModalBody = document.getElementById('messageModalBody');

    // ===== Обработчики событий =====

    // Загрузка сервисов при выборе категории
    if (categorySelect) {
        categorySelect.addEventListener('change', function() {
            const category = this.value;
            loadServicesForCategory(category);
        });
    }

    // Выбор формата при клике (включение/выключение чекбокса)
    formatOptions.forEach(option => {
        option.addEventListener('click', function() {
            const checkbox = this.querySelector('input[type="checkbox"]');
            checkbox.checked = !checkbox.checked;
            this.classList.toggle('selected', checkbox.checked);
        });
    });

    // Добавление нового сервиса по клику на кнопку
    if (addServiceBtn) {
        addServiceBtn.addEventListener('click', function() {
            const category = newCategoryInput.value.trim();
            const service = newServiceInput.value.trim();

            if (!category) {
                showMessage('Ошибка', 'Необходимо указать категорию');
                return;
            }

            if (!service) {
                showMessage('Ошибка', 'Необходимо указать сервис');
                return;
            }

            addService(category, service);
        });
    }

    // Обработка нажатия Enter в поле ввода нового сервиса
    if (newServiceInput) {
        newServiceInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                addServiceBtn.click();
                e.preventDefault();
            }
        });
    }

    // Генерация маршрутов по клику на кнопку
    if (generateBtn) {
        generateBtn.addEventListener('click', function() {
            const selectedFormats = [];
            document.querySelectorAll('input[name="formats"]:checked').forEach(checkbox => {
                selectedFormats.push(checkbox.value);
            });

            if (selectedFormats.length === 0) {
                showMessage('Ошибка', 'Необходимо выбрать хотя бы один формат маршрутов');
                return;
            }

            generateRoutes(selectedFormats);
        });
    }

    // Новая генерация (очистка результатов)
    if (newGenerationBtn) {
        newGenerationBtn.addEventListener('click', function() {
            resultsSection.style.display = 'none';
        });
    }

    // ===== Вспомогательные функции =====

    /**
     * Загрузка сервисов для выбранной категории
     * @param {string} category - Название категории
     */
    function loadServicesForCategory(category) {
        if (!category) {
            servicesList.innerHTML = '<div class="text-muted text-center">Выберите категорию для просмотра сервисов</div>';
            return;
        }

        // Показываем индикатор загрузки
        servicesList.innerHTML = '<div class="text-center"><div class="loading-spinner"></div> Загрузка сервисов...</div>';

        fetch('/api/services')
            .then(response => response.json())
            .then(data => {
                if (data[category] && data[category].length > 0) {
                    let html = '';
                    data[category].forEach(service => {
                        html += `
                            <div class="service-item">
                                <span class="domain-info">${service}</span>
                            </div>
                        `;
                    });
                    servicesList.innerHTML = html;
                } else {
                    servicesList.innerHTML = '<div class="text-muted text-center">Нет сервисов в данной категории</div>';
                }
            })
            .catch(error => {
                console.error('Ошибка:', error);
                servicesList.innerHTML = '<div class="text-danger text-center">Ошибка загрузки сервисов</div>';
            });
    }

    /**
     * Добавление нового сервиса
     * @param {string} category - Название категории
     * @param {string} service - Название сервиса (домен)
     */
    function addService(category, service) {
        // Блокируем кнопку на время запроса
        addServiceBtn.disabled = true;

        fetch('/api/add_service', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ category, service })
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                showMessage('Успех', data.message);
                newServiceInput.value = '';

                // Обновляем список категорий
                if (!document.querySelector(`#existingCategories option[value="${category}"]`)) {
                    const option = document.createElement('option');
                    option.value = category;
                    document.getElementById('existingCategories').appendChild(option);

                    // Добавляем категорию в выпадающий список, если её там нет
                    if (!document.querySelector(`#categorySelect option[value="${category}"]`)) {
                        const selectOption = document.createElement('option');
                        selectOption.value = category;
                        selectOption.textContent = category;
                        categorySelect.appendChild(selectOption);
                    }
                }

                // Если текущая категория совпадает с только что добавленной, обновляем список сервисов
                if (categorySelect.value === category) {
                    loadServicesForCategory(category);
                }
            } else {
                showMessage('Ошибка', data.message);
            }
        })
        .catch(error => {
            console.error('Ошибка:', error);
            showMessage('Ошибка', 'Не удалось добавить сервис. Пожалуйста, попробуйте позже.');
        })
        .finally(() => {
            // Разблокируем кнопку после запроса
            addServiceBtn.disabled = false;
        });
    }

    /**
     * Генерация маршрутов
     * @param {Array} formats - Массив ID выбранных форматов
     */
    function generateRoutes(formats) {
        // Показываем раздел статуса и скрываем результаты
        processingStatus.style.display = 'block';
        resultsSection.style.display = 'none';
        downloadLinks.innerHTML = '';

        // Сбрасываем прогресс
        progressBar.style.width = '0%';
        progressBar.textContent = '0%';
        progressBar.setAttribute('aria-valuenow', '0');
        statusMessage.textContent = 'Инициализация...';

        // Блокируем кнопку генерации
        generateBtn.disabled = true;

        // Отправляем запрос на генерацию
        fetch('/api/generate', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ formats })
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                // Запускаем проверку статуса
                checkStatus();
            } else {
                showMessage('Ошибка', data.message);
                processingStatus.style.display = 'none';
                generateBtn.disabled = false;
            }
        })
        .catch(error => {
            console.error('Ошибка:', error);
            showMessage('Ошибка', 'Не удалось запустить генерацию маршрутов. Пожалуйста, попробуйте позже.');
            processingStatus.style.display = 'none';
            generateBtn.disabled = false;
        });
    }

    /**
     * Проверка статуса генерации
     */
    function checkStatus() {
        fetch('/api/status')
            .then(response => response.json())
            .then(data => {
                // Обновляем прогресс
                progressBar.style.width = data.progress + '%';
                progressBar.textContent = data.progress + '%';
                progressBar.setAttribute('aria-valuenow', data.progress);
                statusMessage.textContent = data.message;

                if (data.is_processing) {
                    // Если обработка продолжается, проверяем статус снова через 1 секунду
                    setTimeout(checkStatus, 1000);
                } else {
                    // Обработка завершена
                    generateBtn.disabled = false;

                    if (data.error) {
                        // Произошла ошибка
                        showMessage('Ошибка', data.error);
                        processingStatus.style.display = 'none';
                    } else {
                        // Успешно завершено
                        processingStatus.style.display = 'none';
                        showResults(data.output_files);
                    }
                }
            })
            .catch(error => {
                console.error('Ошибка при проверке статуса:', error);
                setTimeout(checkStatus, 2000); // Пробуем еще раз через 2 секунды
            });
    }

    /**
     * Показать результаты генерации
     * @param {Object} outputFiles - Объект с путями к сгенерированным файлам
     */
    function showResults(outputFiles) {
        // Создаем ссылки для скачивания
        downloadLinks.innerHTML = '';

        // Получаем информацию о форматах
        fetch('/api/available_formats')
            .then(response => response.json())
            .then(formats => {
                const formatMap = {};
                formats.forEach(format => {
                    formatMap[format.id] = format.name;
                });

                // Создаем кнопки для скачивания каждого формата
                Object.keys(outputFiles).forEach(formatId => {
                    const formatName = formatMap[formatId] || formatId;

                    const btn = document.createElement('a');
                    btn.href = `/api/download/${formatId}`;
                    btn.className = 'btn btn-primary btn-download';
                    btn.innerHTML = `<i class="bi bi-download"></i> ${formatName}`;

                    downloadLinks.appendChild(btn);
                });

                // Показываем раздел с результатами
                resultsSection.style.display = 'block';
            })
            .catch(error => {
                console.error('Ошибка при получении форматов:', error);
                showMessage('Ошибка', 'Не удалось загрузить информацию о форматах. Попробуйте обновить страницу.');
            });
    }

    /**
     * Функция отображения сообщения
     * @param {string} title - Заголовок сообщения
     * @param {string} message - Текст сообщения
     */
    function showMessage(title, message) {
        document.getElementById('messageModalLabel').textContent = title;
        messageModalBody.textContent = message;
        messageModal.show();
    }
});
