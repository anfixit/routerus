from unittest.mock import MagicMock

import pytest
from pydantic_settings import BaseSettings

from app.services.dropbox.dropbox_service import DropboxService
from app.services.service_manager import ServiceManager
from app.services.shadowsocks.shadowsocks_service import ShadowsocksService
from app.services.wireguard.wireguard_service import WireGuardService
from app.services.xray.xray_service import XrayService


@pytest.fixture
def wireguard_service():
    return WireGuardService()


@pytest.fixture
def shadowsocks_service():
    return ShadowsocksService()


@pytest.fixture
def xray_service():
    return XrayService()


@pytest.fixture
def dropbox_service():
    return DropboxService()


@pytest.fixture
def service_manager():
    return ServiceManager()


def test_wireguard_start(mocker, wireguard_service):
    mock_run = mocker.patch("subprocess.run")
    # Эмулируем успешное выполнение команды
    mock_run.return_value = MagicMock(returncode=0)
    wireguard_service.start_service()
    # Проверим, что subprocess.run был вызван хотя бы для настройки и поднятия интерфейса
    assert mock_run.call_count > 0


def test_shadowsocks_start(mocker, shadowsocks_service):
    mock_run = mocker.patch("subprocess.run")
    mock_run.return_value = MagicMock(returncode=0)
    shadowsocks_service.create_config()
    shadowsocks_service.start_service()
    assert mock_run.call_count > 0


def test_xray_start(mocker, xray_service):
    mock_run = mocker.patch("subprocess.run")
    mock_run.return_value = MagicMock(returncode=0)
    xray_service.create_config()
    xray_service.start_service()
    assert mock_run.call_count > 0


def test_dropbox_upload(mocker, dropbox_service):
    mock_post = mocker.patch("requests.post")
    mock_post.return_value = MagicMock(status_code=200, json=lambda: {"name": "test"})
    dropbox_service.upload_file("/tmp/test.log")
    mock_post.assert_called_once()


def test_service_manager_start_all(mocker, service_manager):
    mock_run = mocker.patch("subprocess.run")
    mock_run.return_value = MagicMock(returncode=0)
    service_manager.start_all()
    # Предполагаем, что вызовется несколько раз subprocess.run для разных сервисов
    assert mock_run.call_count > 0
