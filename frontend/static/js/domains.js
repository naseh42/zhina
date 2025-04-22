class DomainManager {
    // 1. بارگذاری دامنه‌ها
    static async loadDomains() {
        const domains = await ZhinaAPI.get('domains');
        this.renderDomains(domains);
    }

    // 2. رندر در جدول
    static renderDomains(domains) {
        const table = document.getElementById('domainsTable');
        table.innerHTML = domains.map(domain => `
            <tr>
                <td>${domain.name}</td>
                <td>${domain.type}</td>
                <td>
                    <button onclick="DomainManager.editDomain('${domain.id}')">
                        ویرایش
                    </button>
                    <button onclick="DomainManager.deleteDomain('${domain.id}')">
                        حذف
                    </button>
                </td>
            </tr>
        `).join('');
    }

    // 3. حذف دامنه
    static async deleteDomain(id) {
        if (confirm('آیا مطمئنید؟')) {
            await ZhinaAPI.delete(`domains/${id}`);
            this.loadDomains(); // بروزرسانی خودکار لیست
        }
    }

    // 4. ویرایش دامنه
    static async editDomain(id) {
        const domain = await ZhinaAPI.get(`domains/${id}`);
        // نمایش فرم ویرایش
    }
}

// راه‌اندازی اولیه
document.addEventListener('DOMContentLoaded', () => {
    DomainManager.loadDomains();
});
