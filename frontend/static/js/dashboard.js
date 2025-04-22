// /static/js/dashboard.js
document.addEventListener('DOMContentLoaded', async () => {
    // بارگذاری داده‌ها
    const updateDashboard = async () => {
        ZhinaAPI.showLoader();
        const data = await ZhinaAPI.fetch('server-stats');
        
        document.getElementById('onlineUsers').textContent = data.users_online;
        document.getElementById('trafficUsage').textContent = ZhinaAPI.formatTraffic(data.traffic_used);
        document.getElementById('serverStatus').textContent = data.xray_status ? 'فعال' : 'غیرفعال';
    };

    // بروزرسانی هر 30 ثانیه
    await updateDashboard();
    setInterval(updateDashboard, 30000);
});
