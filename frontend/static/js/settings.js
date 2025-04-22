class SettingsManager {
    static async init() {
        await this.loadDomains();
        this.setupFormListeners();
    }

    static async loadDomains() {
        const domains = await ZhinaAPI.get('domains');
        this.renderDomainDropdown(domains);
    }

    static renderDomainDropdown(domains) {
        const select = document.getElementById('domainSelect');
        select.innerHTML = domains.map(domain => `
            <option value="${domain.id}">${domain.name}</option>
        `).join('');
    }

    static async saveSettings(e) {
        e.preventDefault();
        const formData = new FormData(e.target);
        await ZhinaAPI.post('settings', Object.fromEntries(formData));
        alert('تنظیمات ذخیره شد!');
    }

    static setupFormListeners() {
        document.getElementById('settingsForm')
            .addEventListener('submit', this.saveSettings.bind(this));
    }
}

document.addEventListener('DOMContentLoaded', () => SettingsManager.init());
