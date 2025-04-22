class Dashboard {
    static async init() {
        await this.loadStats();
        this.setupAutoRefresh();
    }

    static async loadStats() {
        const stats = await ZhinaAPI.get('server-stats');
        this.updateUI(stats);
    }

    static updateUI(stats) {
        document.getElementById('onlineUsers').textContent = stats.users_online;
        document.getElementById('trafficUsage').textContent = `${(stats.traffic_used / 1024).toFixed(2)} گیگابایت`;
        this.renderCharts(stats);
    }

    static renderCharts(stats) {
        // کدهای رسم نمودار...
    }

    static setupAutoRefresh() {
        setInterval(() => this.loadStats(), 30000);
    }
}

document.addEventListener('DOMContentLoaded', () => Dashboard.init());
