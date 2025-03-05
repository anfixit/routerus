"""
Модуль с форматами маршрутов для различных устройств и систем
"""
import ipaddress
from typing import List, Dict, Tuple, Set, Any


class RouteFormatGenerator:
    """
    Класс для генерации маршрутов в различных форматах
    """

    def __init__(self, ips_by_category: Dict[str, Set[str]], ips_by_domain: Dict[str, Set[str]]):
        """
        Инициализация генератора форматов

        Args:
            ips_by_category: IP-адреса по категориям
            ips_by_domain: IP-адреса по доменам
        """
        self.ips_by_category = ips_by_category
        self.ips_by_domain = ips_by_domain

        # Доступные форматы маршрутов
        self.formats = {
            "windows": self._generate_windows_format,
            "linux": self._generate_linux_format,
            "mikrotik": self._generate_mikrotik_format,
            "keenetic": self._generate_keenetic_format,
            "openvpn": self._generate_openvpn_format,
            "wireguard": self._generate_wireguard_format,
            "cisco": self._generate_cisco_format,
            "huawei": self._generate_huawei_format,
            "dlink": self._generate_dlink_format,
            "openwrt": self._generate_openwrt_format,
            "tplink": self._generate_tplink_format,
            "asus": self._generate_asus_format,
            "cidr": self._generate_cidr_format
        }

    def get_available_formats(self) -> List[str]:
        """
        Получение списка доступных форматов

        Returns:
            Список названий доступных форматов
        """
        return list(self.formats.keys())

    def generate_format(self, format_name: str, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация контента в заданном формате

        Args:
            format_name: Название формата
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с контентом в выбранном формате
        """
        if format_name not in self.formats:
            raise ValueError(f"Неизвестный формат: {format_name}")

        return self.formats[format_name](routes, category)

    def _generate_windows_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате Windows

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для Windows
        """
        header = f":: Маршруты для категории {category}\n" if category else ":: Маршруты для российских сервисов\n"
        content = header + "\n"

        for ip, mask, description in routes:
            content += f"route ADD {ip} MASK {mask} 0.0.0.0 :: {description}\n"

        return content

    def _generate_linux_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате Linux/Unix

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для Linux/Unix
        """
        header = f"# Маршруты для категории {category}\n" if category else "# Маршруты для российских сервисов\n"
        content = header + "\n"

        for ip, mask, description in routes:
            # Преобразование маски в CIDR нотацию
            try:
                cidr = ipaddress.IPv4Network(f"{ip}/{mask}", strict=False).prefixlen
                content += f"ip route add {ip}/{cidr} via %gateway% dev %interface% # {description}\n"
            except ValueError:
                content += f"# Ошибка в маршруте: {ip}/{mask} # {description}\n"

        content += "\n# Замените %gateway% на IP-адрес вашего шлюза и %interface% на имя интерфейса\n"

        return content

    def _generate_mikrotik_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате MikroTik

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для MikroTik
        """
        list_name = category.replace(" ", "_") if category else "RU_Services"
        header = f"# Маршруты для категории {category}\n" if category else "# Маршруты для российских сервисов\n"
        content = header + "\n"

        content += f"/ip firewall address-list\n"

        for ip, mask, description in routes:
            # Преобразование маски в CIDR нотацию
            try:
                cidr = ipaddress.IPv4Network(f"{ip}/{mask}", strict=False).prefixlen
                content += f"add list={list_name} address={ip}/{cidr} comment=\"{description}\"\n"
            except ValueError:
                content += f"# Ошибка в маршруте: {ip}/{mask} # {description}\n"

        return content

    def _generate_keenetic_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате Keenetic

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для Keenetic
        """
        header = f"! Маршруты для категории {category}\n" if category else "! Маршруты для российских сервисов\n"
        content = header + "\n"
        content += "! Сначала переходим в режим настройки\n"
        content += "configure terminal\n\n"

        for ip, mask, description in routes:
            # Преобразование маски в CIDR нотацию
            try:
                network = ipaddress.IPv4Network(f"{ip}/{mask}", strict=False)
                network_ip = str(network.network_address)
                network_mask = str(network.netmask)

                content += f"! Добавление маршрута для {description}\n"
                content += f"ip route {network_ip} {network_mask} interface global\n"
                content += f"ip route {network_ip} {network_mask} name \"{description}\"\n"
                content += f"ip route {network_ip} {network_mask} exclusive\n\n"
            except ValueError:
                content += f"! Ошибка в маршруте: {ip}/{mask} # {description}\n\n"

        content += "! Сохраняем конфигурацию\n"
        content += "end\n"
        content += "system configuration save\n"

        return content

    def _generate_openvpn_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате OpenVPN

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для OpenVPN
        """
        header = f"# Маршруты для категории {category}\n" if category else "# Маршруты для российских сервисов\n"
        content = header + "\n"

        for ip, mask, description in routes:
            content += f"push \"route {ip} {mask}\" # {description}\n"

        return content

    def _generate_wireguard_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате WireGuard

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для WireGuard
        """
        header = f"# Маршруты для категории {category}\n" if category else "# Маршруты для российских сервисов\n"
        content = header + "\n"
        content += "# Добавьте эти маршруты в секцию [Interface] файла конфигурации WireGuard\n"
        content += "# AllowedIPs = 0.0.0.0/0, ::/0\n\n"
        content += "# Или используйте следующие маршруты для исключения российских сервисов:\n"

        allowed_ips = []

        for ip, mask, description in routes:
            try:
                cidr = ipaddress.IPv4Network(f"{ip}/{mask}", strict=False).prefixlen
                allowed_ips.append(f"{ip}/{cidr}")
            except ValueError:
                content += f"# Ошибка в маршруте: {ip}/{mask} # {description}\n"

        content += "AllowedIPs = " + ", ".join(allowed_ips) + "\n"

        return content

    def _generate_cisco_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате Cisco IOS

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для Cisco IOS
        """
        header = f"! Маршруты для категории {category}\n" if category else "! Маршруты для российских сервисов\n"
        content = header + "\n"

        content += "configure terminal\n"

        for ip, mask, description in routes:
            # Для Cisco нужно инвертировать маску
            try:
                network = ipaddress.IPv4Network(f"{ip}/{mask}", strict=False)
                wildcard_mask = str(ipaddress.IPv4Address(int(network.netmask) ^ 0xFFFFFFFF))

                content += f"ip route {ip} {wildcard_mask} %gateway% ! {description}\n"
            except ValueError:
                content += f"! Ошибка в маршруте: {ip}/{mask} # {description}\n"

        content += "end\n"
        content += "write memory\n"

        return content

    def _generate_huawei_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате Huawei

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для Huawei
        """
        header = f"# Маршруты для категории {category}\n" if category else "# Маршруты для российских сервисов\n"
        content = header + "\n"

        content += "system-view\n"

        for ip, mask, description in routes:
            content += f"ip route-static {ip} {mask} %gateway% description \"{description}\"\n"

        content += "commit\n"
        content += "quit\n"

        return content

    def _generate_dlink_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате D-Link

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для D-Link
        """
        header = f"# Маршруты для категории {category}\n" if category else "# Маршруты для российских сервисов\n"
        content = header + "\n"

        for ip, mask, description in routes:
            content += f"create iproute {ip} {mask} %gateway% 1 # {description}\n"

        content += "save\n"

        return content

    def _generate_openwrt_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате OpenWrt

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для OpenWrt
        """
        header = f"# Маршруты для категории {category}\n" if category else "# Маршруты для российских сервисов\n"
        content = header + "\n"

        for ip, mask, description in routes:
            try:
                cidr = ipaddress.IPv4Network(f"{ip}/{mask}", strict=False).prefixlen
                content += f"uci add network route\n"
                content += f"uci set network.@route[-1].interface='wan'\n"
                content += f"uci set network.@route[-1].target='{ip}'\n"
                content += f"uci set network.@route[-1].netmask='{mask}'\n"
                content += f"uci set network.@route[-1].gateway='%gateway%'\n"
                content += f"# {description}\n\n"
            except ValueError:
                content += f"# Ошибка в маршруте: {ip}/{mask} # {description}\n\n"

        content += "uci commit network\n"
        content += "/etc/init.d/network restart\n"

        return content

    def _generate_tplink_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате TP-Link

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для TP-Link
        """
        header = f"# Маршруты для категории {category}\n" if category else "# Маршруты для российских сервисов\n"
        content = header + "\n"
        content += "# Для настройки статических маршрутов на TP-Link роутерах:\n"
        content += "# 1. Зайдите в веб-интерфейс администратора\n"
        content += "# 2. Перейдите в раздел Сеть -> Статические маршруты\n"
        content += "# 3. Добавьте следующие маршруты:\n\n"

        for i, (ip, mask, description) in enumerate(routes, 1):
            content += f"# {i}. Сеть назначения: {ip}, Маска подсети: {mask}, Шлюз: [Ваш шлюз], Описание: {description}\n"

        return content

    def _generate_asus_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате ASUS

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами для ASUS
        """
        header = f"# Маршруты для категории {category}\n" if category else "# Маршруты для российских сервисов\n"
        content = header + "\n"
        content += "# Для настройки статических маршрутов на ASUS роутерах:\n"
        content += "# 1. Зайдите в веб-интерфейс администратора\n"
        content += "# 2. Перейдите в раздел Дополнительно -> Статические маршруты\n"
        content += "# 3. Добавьте следующие маршруты:\n\n"

        for i, (ip, mask, description) in enumerate(routes, 1):
            try:
                cidr = ipaddress.IPv4Network(f"{ip}/{mask}", strict=False).prefixlen
                content += f"# {i}. Сеть: {ip}/{cidr}, Шлюз: [Ваш шлюз], Интерфейс: WAN, Описание: {description}\n"
            except ValueError:
                content += f"# Ошибка в маршруте: {ip}/{mask} # {description}\n"

        return content

    def _generate_cidr_format(self, routes: List[Tuple[str, str, str]], category: str = None) -> str:
        """
        Генерация маршрутов в формате CIDR

        Args:
            routes: Список маршрутов (IP, маска, описание)
            category: Категория сервисов (опционально)

        Returns:
            Строка с маршрутами в формате CIDR
        """
        header = f"# Маршруты для категории {category}\n" if category else "# Маршруты для российских сервисов\n"
        content = header + "\n"

        for ip, mask, description in routes:
            try:
                cidr = ipaddress.IPv4Network(f"{ip}/{mask}", strict=False).prefixlen
                content += f"{ip}/{cidr} # {description}\n"
            except ValueError:
                content += f"# Ошибка в маршруте: {ip}/{mask} # {description}\n"

        return content
