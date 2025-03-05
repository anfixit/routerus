from flask import Flask, render_template, request, jsonify, send_file, redirect, url_for
import os
import tempfile
import shutil
import zipfile
import time
import json
import threading
import logging
from routerus import RouteRus
from route_formats import RouteFormatGenerator

app = Flask(__name__)

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("routerus_web.log", encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Глобальные переменные
SERVICES_FILE = os.path.join('data', 'russian_services.txt')
ROUTES_DIR = os.path.join('routes')
AVAILABLE_FORMATS = [
    {"id": "windows", "name": "Windows Route"},
    {"id": "linux", "name": "Linux/Unix Route"},
    {"id": "mikrotik", "name": "MikroTik"},
    {"id": "keenetic", "name": "Keenetic"},
    {"id": "openvpn", "name": "OpenVPN"},
    {"id": "wireguard", "name": "WireGuard"},
    {"id": "cisco", "name": "Cisco IOS"},
    {"id": "huawei", "name": "Huawei"},
    {"id": "dlink", "name": "D-Link"},
    {"id": "openwrt", "name": "OpenWrt"},
    {"id": "tplink", "name": "TP-Link"},
    {"id": "asus", "name": "ASUS"},
    {"id": "cidr", "name": "CIDR"}
]

# Глобальные переменные для отслеживания процесса
processing_status = {
    "is_processing": False,
    "progress": 0,
    "message": "",
    "output_files": {},
    "error": None
}


def reset_status():
    """Сброс статуса обработки"""
    processing_status["is_processing"] = False
    processing_status["progress"] = 0
    processing_status["message"] = ""
    processing_status["output_files"] = {}
    processing_status["error"] = None


def load_services():
    """
    Загрузка сервисов из файла

    Returns:
        Словарь категорий с сервисами
    """
    try:
        if not os.path.exists(SERVICES_FILE):
            # Создаем директорию, если её нет
            os.makedirs(os.path.dirname(SERVICES_FILE), exist_ok=True)
            # Создаем пустой файл
            with open(SERVICES_FILE, 'w', encoding='utf-8') as f:
                f.write("")
            return {}

        services_by_category = {}
        current_category = None

        with open(SERVICES_FILE, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()

                if not line:
                    # Пустая строка - возможное начало новой категории
                    continue

                # Проверяем, является ли строка заголовком категории
                if line and not line.startswith('#') and not '.' in line:
                    current_category = line
                    if current_category not in services_by_category:
                        services_by_category[current_category] = []
                elif current_category and '.' in line:
                    # Это сервис
                    services_by_category[current_category].append(line)

        return services_by_category

    except Exception as e:
        logger.error(f"Ошибка загрузки сервисов: {e}")
        return {}


def save_services(services_by_category):
    """
    Сохранение сервисов в файл

    Args:
        services_by_category: Словарь категорий с сервисами
    """
    try:
        # Создаем директорию, если её нет
        os.makedirs(os.path.dirname(SERVICES_FILE), exist_ok=True)

        with open(SERVICES_FILE, 'w', encoding='utf-8') as f:
            for category, services in services_by_category.items():
                f.write(f"{category}\n\n")
                for service in services:
                    f.write(f"{service}\n")
                f.write("\n")

        logger.info(f"Сервисы успешно сохранены в {SERVICES_FILE}")

    except Exception as e:
        logger.error(f"Ошибка сохранения сервисов: {e}")


def add_service(category, service):
    """
    Добавление нового сервиса в категорию

    Args:
        category: Название категории
        service: Название сервиса

    Returns:
        Успешность операции
    """
    try:
        services_by_category = load_services()

        # Создаем категорию, если её нет
        if category not in services_by_category:
            services_by_category[category] = []

        # Проверяем, что сервис еще не добавлен
        if service not in services_by_category[category]:
            services_by_category[category].append(service)
            save_services(services_by_category)
            return True

        return False

    except Exception as e:
        logger.error(f"Ошибка добавления сервиса: {e}")
        return False


def process_routes(formats):
    """
    Обработка маршрутов

    Args:
        formats: Список форматов для генерации
    """
    try:
        processing_status["is_processing"] = True
        processing_status["progress"] = 5
        processing_status["message"] = "Начало обработки..."

        # Создаем директории для выходных файлов
        if not os.path.exists(ROUTES_DIR):
            os.makedirs(ROUTES_DIR)

        for format_id in formats:
            format_dir = os.path.join(ROUTES_DIR, format_id)
            if not os.path.exists(format_dir):
                os.makedirs(format_dir)

        # Инициализируем и запускаем RouteRus
        config = {
            "input_file": SERVICES_FILE,
            "output_dir": ROUTES_DIR
        }

        processing_status["progress"] = 10
        processing_status["message"] = "Инициализация генератора маршрутов..."

        route_generator = RouteRus(config)

        # Загрузка доменов
        processing_status["message"] = "Загрузка доменов из файла сервисов..."
        processing_status["progress"] = 15
        route_generator.load_domains_from_file(SERVICES_FILE)

        # Разрешение доменов в IP-адреса
        processing_status["message"] = "Получение IP-адресов для доменов..."
        processing_status["progress"] = 25
        route_generator.resolve_all_domains()
        processing_status["progress"] = 75

        # Создание файлов маршрутов
        processing_status["message"] = "Создание файлов с маршрутами..."
        processing_status["progress"] = 80
        generated_files = route_generator.generate_route_files(ROUTES_DIR, formats)
        processing_status["progress"] = 95

        # Создание ZIP-архива для каждого формата
        processing_status["message"] = "Создание ZIP-архивов с результатами..."

        for format_id in formats:
            format_dir = os.path.join(ROUTES_DIR, format_id)
            zip_file_path = os.path.join(ROUTES_DIR, f"{format_id}_routes.zip")

            with zipfile.ZipFile(zip_file_path, 'w') as zipf:
                for root, _, files in os.walk(format_dir):
                    for file in files:
                        file_path = os.path.join(root, file)
                        zipf.write(
                            file_path,
                            os.path.relpath(file_path, format_dir)
                        )

            processing_status["output_files"][format_id] = zip_file_path

        processing_status["message"] = "Обработка завершена"
        processing_status["progress"] = 100

    except Exception as e:
        logger.error(f"Ошибка при обработке маршрутов: {e}")
        processing_status["message"] = f"Ошибка: {str(e)}"
        processing_status["error"] = str(e)
    finally:
        processing_status["is_processing"] = False


@app.route('/')
def index():
    """Главная страница"""
    services_by_category = load_services()
    return render_template(
        'index.html',
        services_by_category=services_by_category,
        formats=AVAILABLE_FORMATS
    )


@app.route('/api/services')
def get_services():
    """API для получения списка сервисов"""
    services_by_category = load_services()
    return jsonify(services_by_category)


@app.route('/api/add_service', methods=['POST'])
def api_add_service():
    """API для добавления нового сервиса"""
    try:
        data = request.json
        category = data.get('category')
        service = data.get('service')

        if not category or not service:
            return jsonify({"success": False, "message": "Необходимо указать категорию и сервис"})

        # Проверка формата сервиса (должен быть доменом)
        if not '.' in service:
            return jsonify({"success": False, "message": "Сервис должен быть доменным именем (например, example.ru)"})

        result = add_service(category, service)

        if result:
            return jsonify({"success": True, "message": f"Сервис {service} успешно добавлен в категорию {category}"})
        else:
            return jsonify({"success": False, "message": f"Сервис {service} уже существует в категории {category}"})

    except Exception as e:
        logger.error(f"Ошибка при добавлении сервиса: {e}")
        return jsonify({"success": False, "message": f"Ошибка: {str(e)}"})


@app.route('/api/generate', methods=['POST'])
def api_generate():
    """API для запуска генерации маршрутов"""
    try:
        data = request.json
        formats = data.get('formats', [])

        if not formats:
            return jsonify({
                "success": False,
                "message": "Необходимо выбрать хотя бы один формат"
            })

        # Проверяем валидность форматов
        valid_formats = [f["id"] for f in AVAILABLE_FORMATS]
        for format_id in formats:
            if format_id not in valid_formats:
                return jsonify({
                    "success": False,
                    "message": f"Неверный формат: {format_id}"
                })

        # Сброс статуса предыдущей обработки
        reset_status()

        # Запуск обработки в отдельном потоке
        thread = threading.Thread(
            target=process_routes,
            args=(formats,)
        )
        thread.daemon = True
        thread.start()

        return jsonify({
            "success": True,
            "message": "Обработка началась"
        })

    except Exception as e:
        logger.error(f"Ошибка при запуске генерации: {e}")
        return jsonify({
            "success": False,
            "message": f"Ошибка: {str(e)}"
        })


@app.route('/api/status')
def api_status():
    """API для получения статуса обработки"""
    return jsonify(processing_status)


@app.route('/api/download/<format_id>')
def api_download(format_id):
    """API для скачивания результата"""
    if not processing_status["output_files"] or format_id not in processing_status["output_files"]:
        return jsonify({
            "success": False,
            "message": "Файл с результатами не найден"
        }), 404

    zip_file_path = processing_status["output_files"][format_id]

    if not os.path.exists(zip_file_path):
        return jsonify({
            "success": False,
            "message": "Файл с результатами не найден"
        }), 404

    # Находим имя формата по ID
    format_name = next((f["name"] for f in AVAILABLE_FORMATS if f["id"] == format_id), format_id)

    return send_file(
        zip_file_path,
        as_attachment=True,
        download_name=f"{format_name}_routes.zip",
        mimetype='application/zip'
    )


@app.route('/download/<format_id>')
def download(format_id):
    """Страница скачивания результата"""
    return redirect(url_for('api_download', format_id=format_id))


@app.route('/api/available_formats')
def api_available_formats():
    """API для получения списка доступных форматов"""
    return jsonify(AVAILABLE_FORMATS)


if __name__ == '__main__':
    # Создаем директорию для данных, если её нет
    os.makedirs('data', exist_ok=True)

    # Создаем директорию для маршрутов, если её нет
    os.makedirs(ROUTES_DIR, exist_ok=True)

    # Запускаем приложение
    app.run(host='0.0.0.0', port=5000, debug=True)
