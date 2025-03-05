import os
import re
import logging
import argparse
import ipaddress
import requests
import time
import random
from concurrent.futures import ThreadPoolExecutor, as_completed
from collections import defaultdict
from tqdm import tqdm
from bs4 import BeautifulSoup
from typing import List, Dict, Tuple, Set, Any, Optional

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("routerus.log", encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class RouteRus:
    def __init__(self, config: Dict[str, Any]):
        """
        Инициализация класса RouteRus

        Args:
            config: Словарь с настройками
        """
        self.config = config
        self.domains_by_category = defaultdict(list)
        self.ips_by_category = defaultdict(set)
        self.ips_by_domain = defaultdict(set)
        self.domain_failed = []
        self.total_domains = 0
        self.total_ips = 0

        # Настройки HTTP запросов
        self.headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Connection": "keep-alive",
            "Upgrade-Insecure-Requests": "1",
            "Cache-Control": "max-age=0",
        }

    def load_domains_from_file(self, file_path: str) -> None:
        """
        Загрузка доменов из текстового файла

        Args:
            file_path: Путь к текстовому файлу
        """
        if not os.path.exists(file_path):
            logger.error(f"Файл {file_path} не найден")
            return

        logger.info(f"Загрузка доменов из файла {file_path}")

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

                # Ищем группы сервисов (банки, госсервисы и т.д.)
                sections = re.split(r'\n\s*\n|\n(?=[А-Я][\wа-яА-Я]*\s*\n)', content)

                for section in sections:
                    lines = section.strip().split('\n')
                    if not lines or len(lines) < 2:
                        continue

                    category_line = lines[0].strip()

                    # Очистка категории от специальных символов
                    category = category_line.strip()

                    # Добавляем домены из этого раздела
                    for line in lines[1:]:
                        line = line.strip()
                        if not line or line.startswith('#'):
                            continue

                        # Проверка на URL-формат и извлечение домена
                        domain_pattern = re.compile(
                            r'(?:https?://)?(?:www\.)?([a-zA-Z0-9][-a-zA-Z0-9]*(?:\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)')
                        match = domain_pattern.search(line)
                        if match:
                            domain = match.group(1)
                        else:
                            # Если это не URL, проверяем, является ли строка доменом
                            parts = re.split(r'[–\s–-]', line, 1)
                            if len(parts) > 0:
                                domain_candidate = parts[0].strip()
                                # Проверка на формат домена
                                if re.match(r'^[a-zA-Z0-9][-a-zA-Z0-9]*(?:\.[a-zA-Z0-9][-a-zA-Z0-9]*)+$',
                                            domain_candidate):
                                    domain = domain_candidate
                                else:
                                    continue
                            else:
                                continue

                        self.domains_by_category[category].append(domain)
                        self.total_domains += 1

                logger.info(f"Загружено {self.total_domains} доменов из {len(self.domains_by_category)} категорий")

        except Exception as e:
            logger.error(f"Ошибка при загрузке доменов из файла: {e}")

    def _parse_rapiddns_page(self, url: str, attempt: int = 1, max_attempts: int = 3) -> Set[str]:
        """
        Парсинг страницы rapiddns.io для получения IP-адресов

        Args:
            url: URL для парсинга
            attempt: Текущая попытка
            max_attempts: Максимальное количество попыток

        Returns:
            Множество найденных IP-адресов
        """
        ip_addresses = set()

        try:
            # Случайная задержка для предотвращения блокировки
            sleep_time = random.uniform(1.0, 3.0)
            time.sleep(sleep_time)

            response = requests.get(url, headers=self.headers, timeout=15)
            response.raise_for_status()

            soup = BeautifulSoup(response.text, 'html.parser')
            table = soup.find('table', {'class': 'table'})

            if table:
                tbody = table.find('tbody')
                if tbody:
                    rows = tbody.find_all('tr')
                    for row in rows:
                        cols = row.find_all('td')
                        if len(cols) >= 4 and cols[2].text.strip() == 'A':
                            ip = cols[3].text.strip()
                            if re.match(r'^(\d{1,3}\.){3}\d{1,3}$', ip):  # Валидация IPv4
                                ip_addresses.add(ip)

            return ip_addresses

        except requests.exceptions.RequestException as e:
            logger.warning(f"Ошибка при запросе {url}: {e}")
            if attempt < max_attempts:
                # Экспоненциальная задержка перед повторной попыткой
                backoff_time = 2 ** attempt + random.uniform(0, 1)
                time.sleep(backoff_time)
                return self._parse_rapiddns_page(url, attempt + 1, max_attempts)
            else:
                logger.error(f"Превышено максимальное количество попыток для {url}")
                return ip_addresses
        except Exception as e:
            logger.error(f"Непредвиденная ошибка при парсинге {url}: {e}")
            return ip_addresses

    def get_ips_from_rapiddns(self, domain: str) -> Set[str]:
        """
        Получение IP-адресов для домена через rapiddns.io

        Args:
            domain: Доменное имя

        Returns:
            Множество IP-адресов
        """
        ip_addresses = set()

        # Поиск точного соответствия
        url = f"https://rapiddns.io/s/{domain}?full=1"
        exact_ips = self._parse_rapiddns_page(url)
        ip_addresses.update(exact_ips)

        # Поиск поддоменов
        if len(exact_ips) < 5:  # Если найдено мало IP, ищем поддомены
            url = f"https://rapiddns.io/subdomain/{domain}?full=1"
            subdomain_ips = self._parse_rapiddns_page(url)
            ip_addresses.update(subdomain_ips)

        logger.debug(f"Найдено {len(ip_addresses)} IP-адресов для домена {domain} через rapiddns.io")
        return ip_addresses

    def resolve_domain(self, domain: str, category: str) -> None:
        """
        Получение IP-адресов для домена

        Args:
            domain: Доменное имя
            category: Категория сервиса
        """
        try:
            logger.debug(f"Получение IP для домена {domain}")

            # Получение IP-адресов через rapiddns.io
            ip_addresses = self.get_ips_from_rapiddns(domain)

            if ip_addresses:
                self.ips_by_domain[domain] = ip_addresses
                self.ips_by_category[category].update(ip_addresses)
                self.total_ips += len(ip_addresses)
                logger.debug(f"Для домена {domain} найдено {len(ip_addresses)} IP-адресов")
            else:
                # Если через rapiddns.io не нашлось IP, пробуем использовать стандартное DNS-разрешение
                try:
                    import socket
                    ip_list = socket.gethostbyname_ex(domain)[2]
                    ip_addresses = set(ip for ip in ip_list if re.match(r'^(\d{1,3}\.){3}\d{1,3}$', ip))

                    if ip_addresses:
                        self.ips_by_domain[domain] = ip_addresses
                        self.ips_by_category[category].update(ip_addresses)
                        self.total_ips += len(ip_addresses)
                        logger.debug(f"Для домена {domain} найдено {len(ip_addresses)} IP-адресов через DNS")
                    else:
                        self.domain_failed.append(domain)
                        logger.debug(f"Для домена {domain} не найдено IP-адресов")
                except Exception as e:
                    self.domain_failed.append(domain)
                    logger.debug(f"Ошибка DNS-разрешения для домена {domain}: {e}")

        except Exception as e:
            self.domain_failed.append(domain)
            logger.debug(f"Ошибка при получении IP для домена {domain}: {e}")

    def resolve_all_domains(self) -> None:
        """
        Получение IP-адресов для всех доменов с использованием многопоточности
        """
        logger.info("Получение IP-адресов для всех доменов...")
        max_workers = min(10, self.total_domains)  # Ограничиваем число потоков, чтобы не перегружать сервис
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_domain = {}

            for category, domains in self.domains_by_category.items():
                for domain in domains:
                    future = executor.submit(self.resolve_domain, domain, category)
                    future_to_domain[future] = domain

            # Прогресс-бар для отслеживания выполнения
            with tqdm(total=len(future_to_domain), desc="Обработка доменов") as pbar:
                for future in as_completed(future_to_domain):
                    domain = future_to_domain[future]
                    try:
                        future.result()
                    except Exception as e:
                        logger.error(f"Ошибка при обработке домена {domain}: {e}")
                    pbar.update(1)

        logger.info(
            f"Получено {self.total_ips} IP-адресов для {self.total_domains - len(self.domain_failed)} из {self.total_domains} доменов")
        logger.info(f"Не удалось получить IP для {len(self.domain_failed)} доменов")

    def consolidate_networks(self, category: str) -> List[Tuple[str, str, str]]:
        """
        Объединение IP-адресов в подсети для оптимизации маршрутов

        Args:
            category: Категория сервиса

        Returns:
            Список кортежей (IP, маска, описание)
        """
        if category not in self.ips_by_category:
            return []

        consolidated = []
        ips = self.ips_by_category[category]

        # Группировка IP-адресов по первым октетам
        ip_groups = defaultdict(list)
        for ip in ips:
            octets = ip.split('.')
            if len(octets) == 4:
                prefix_1 = octets[0]
                prefix_2 = '.'.join(octets[:2])
                prefix_3 = '.'.join(octets[:3])

                ip_groups[prefix_1].append(ip)
                ip_groups[prefix_2].append(ip)
                ip_groups[prefix_3].append(ip)

        # Объединяем IP в подсети, начиная с более крупных
        processed_ips = set()

        # /16 подсети (объединение по первым двум октетам, если более 20 IP)
        for prefix in [key for key in ip_groups.keys() if len(key.split('.')) == 2]:
            ips_in_group = [ip for ip in ip_groups[prefix] if ip not in processed_ips]
            if len(ips_in_group) > 20:
                network = f"{prefix}.0.0"
                mask = "255.255.0.0"
                description = f"{category} subnet {prefix}.0.0/16"
                consolidated.append((network, mask, description))
                processed_ips.update(ips_in_group)

        # /24 подсети (объединение по первым трем октетам, если более 5 IP)
        for prefix in [key for key in ip_groups.keys() if len(key.split('.')) == 3]:
            ips_in_group = [ip for ip in ip_groups[prefix] if ip not in processed_ips]
            if len(ips_in_group) > 5:
                network = f"{prefix}.0"
                mask = "255.255.255.0"
                description = f"{category} subnet {prefix}.0/24"
                consolidated.append((network, mask, description))
                processed_ips.update(ips_in_group)

        # Оставшиеся IP добавляем по отдельности с маской /32
        for ip in ips:
            if ip not in processed_ips:
                mask = "255.255.255.255"

                # Находим домен, соответствующий этому IP
                domain = None
                for d, d_ips in self.ips_by_domain.items():
                    if ip in d_ips:
                        domain = d
                        break

                description = f"{category} {domain}" if domain else f"{category} IP {ip}"
                consolidated.append((ip, mask, description))

        logger.info(f"Категория {category}: объединено {len(ips)} IP-адресов в {len(consolidated)} маршрутов")
        return consolidated

    def generate_route_files(self, output_dir: str, formats: List[str] = None) -> Dict[str, str]:
        """
        Создание файлов с маршрутами в различных форматах

        Args:
            output_dir: Директория для сохранения файлов
            formats: Список форматов для генерации, по умолчанию все доступные

        Returns:
            Словарь путей к сгенерированным файлам
        """
        from route_formats import RouteFormatGenerator

        logger.info(f"Создание файлов с маршрутами в директории {output_dir}")

        # Инициализация генератора форматов
        format_generator = RouteFormatGenerator(self.ips_by_category, self.ips_by_domain)

        # Директории для каждого формата
        format_dirs = {}
        for format_name in format_generator.get_available_formats():
            if formats is None or format_name in formats:
                format_dir = os.path.join(output_dir, format_name)
                if not os.path.exists(format_dir):
                    os.makedirs(format_dir)
                format_dirs[format_name] = format_dir

        # Сгенерированные файлы
        generated_files = {}

        # Генерация файлов по категориям для каждого формата
        for format_name, format_dir in format_dirs.items():
            logger.info(f"Генерация файлов для формата {format_name}")

            # Отдельные файлы по категориям
            for category in self.ips_by_category.keys():
                if not self.ips_by_category[category]:
                    continue

                # Получаем оптимизированные маршруты
                routes = self.consolidate_networks(category)

                # Генерация файла маршрутов
                file_name = f"{category}.txt"
                output_path = os.path.join(format_dir, file_name)

                # Получение контента в нужном формате
                content = format_generator.generate_format(format_name, routes, category=category)

                # Сохранение в файл
                with open(output_path, 'w', encoding='utf-8') as f:
                    f.write(content)

                key = f"{format_name}_{category}"
                generated_files[key] = output_path
                logger.info(f"Создан файл {output_path}")

            # Общий файл для всех категорий
            all_routes = []
            for category in self.ips_by_category.keys():
                if not self.ips_by_category[category]:
                    continue
                all_routes.extend(self.consolidate_networks(category))

            file_name = "all_routes.txt"
            output_path = os.path.join(format_dir, file_name)

            # Получение контента в нужном формате
            content = format_generator.generate_format(format_name, all_routes)

            # Сохранение в файл
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(content)

            key = f"{format_name}_all"
            generated_files[key] = output_path
            logger.info(f"Создан общий файл {output_path}")

        return generated_files

    def run(self, formats: List[str] = None) -> Dict[str, str]:
        """
        Основной метод для запуска обработки

        Args:
            formats: Список форматов для генерации, по умолчанию все доступные

        Returns:
            Словарь путей к сгенерированным файлам
        """
        logger.info("Запуск процесса генерации маршрутов...")

        # Загрузка доменов из файла
        self.load_domains_from_file(self.config["input_file"])

        # Разрешение доменов в IP-адреса
        self.resolve_all_domains()

        # Создание файлов маршрутов
        generated_files = self.generate_route_files(self.config["output_dir"], formats)

        logger.info("Процесс завершен!")
        return generated_files


def main():
    """
    Основная функция для запуска из командной строки
    """
    parser = argparse.ArgumentParser(description="Генератор маршрутов для российских сервисов")
    parser.add_argument("--input", "-i", required=True, help="Путь к текстовому файлу со списком российских сервисов")
    parser.add_argument("--output", "-o", default="routes", help="Директория для сохранения файлов")
    parser.add_argument("--formats", "-f", nargs="+",
                        help="Форматы для генерации (windows, linux, mikrotik, keenetic, openvpn, wireguard)")

    args = parser.parse_args()

    config = {
        "input_file": args.input,
        "output_dir": args.output
    }

    route_generator = RouteRus(config)
    route_generator.run(args.formats)


if __name__ == "__main__":
    main()
