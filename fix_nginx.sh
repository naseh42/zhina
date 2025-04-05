#!/bin/bash

# 1. بررسی وضعیت Nginx
echo "بررسی وضعیت سرویس Nginx ..."
systemctl status nginx | grep "Active"

# 2. بررسی پیکربندی Nginx
echo "بررسی پیکربندی Nginx ..."
nginx -t

# 3. بررسی دسترسی به دایرکتوری و فایل‌های frontend
echo "بررسی دسترسی به دایرکتوری frontend ..."
if [ ! -d "/opt/zhina/frontend" ]; then
    echo "دایرکتوری frontend پیدا نشد. سعی در ایجاد آن ..."
    sudo mkdir -p /opt/zhina/frontend
fi
echo "اعطای دسترسی‌ها به دایرکتوری frontend ..."
sudo chown -R www-data:www-data /opt/zhina/frontend
sudo chmod -R 777 /opt/zhina/frontend

# 4. بررسی فایل .env
if [ ! -f "/opt/zhina/frontend/.env" ]; then
    echo "فایل .env پیدا نشد. لطفاً آن را در دایرکتوری /opt/zhina/frontend قرار دهید."
else
    echo "فایل .env پیدا شد."
fi

# 5. بررسی وضعیت سرور Zhina
echo "بررسی وضعیت سرویس zhina-panel ..."
systemctl status zhina-panel | grep "Active"

# 6. بررسی اتصال به بک‌اند (اگر Nginx و Zhina متصل نیستند)
echo "بررسی اتصال به بک‌اند ..."
if ! curl --silent --head http://127.0.0.1:8001; then
    echo "اتصال به بک‌اند برقرار نیست! شروع به ری‌استارت کردن سرویس‌ها ..."
    sudo systemctl restart nginx
    sudo systemctl restart zhina-panel
    echo "سرویس‌ها ری‌استارت شدند."
else
    echo "اتصال به بک‌اند برقرار است."
fi

# 7. بررسی لاگ‌ها برای مشکلات اضافی
echo "بررسی لاگ‌های Nginx ..."
tail -n 20 /var/log/nginx/error.log

# بررسی وجود فایل‌های گم‌شده در لاگ‌های Nginx
for missing_file in "containers/json" "version" "admin/assets/js/views/login.js"; do
    if [ ! -f "/opt/zhina/frontend/$missing_file" ]; then
        echo "فایل /opt/zhina/frontend/$missing_file پیدا نشد. لطفاً آن را بررسی کنید."
    fi
done

echo "بررسی لاگ‌های Zhina ..."
if [ -f "/var/log/zhina/zhina-panel.log" ]; then
    tail -n 20 /var/log/zhina/zhina-panel.log
else
    echo "فایل لاگ zhina-panel پیدا نشد. بررسی کنید که فایل‌ها وجود دارند."
fi

echo "پایان بررسی‌ها."
