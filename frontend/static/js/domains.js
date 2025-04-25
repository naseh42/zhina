class DomainManager {
    // 1. بارگذاری دامنه‌ها
    static async loadDomains() {
        const domains = await ZhinaAPI.get('domains');
        this.renderDomains(domains);
        this.populateSubdomains(domains);  // پر کردن زیرمجموعه‌ها برای سابسکرپشن
    }

    // 2. رندر دامنه‌ها در جدول
    static renderDomains(domains) {
        const table = document.getElementById('domainsTableBody');
        table.innerHTML = domains.map(domain => `
            <tr>
                <td>${domain.name}</td>
                <td>${domain.type}</td>
                <td>${domain.ssl_status ? 'فعال' : 'غیرفعال'}</td>
                <td>
                    <button onclick="DomainManager.editDomain('${domain.id}')">ویرایش</button>
                    <button onclick="DomainManager.deleteDomain('${domain.id}')">حذف</button>
                </td>
            </tr>
        `).join('');
    }

    // 3. پر کردن فیلد زیرمجموعه‌ها
    static populateSubdomains(domains) {
        const subdomainsSelect = document.getElementById('subdomains');
        subdomainsSelect.innerHTML = domains.filter(domain => domain.type !== 'subscription')
            .map(domain => `<option value="${domain.id}">${domain.name}</option>`)
            .join('');
    }

    // 4. افزودن دامنه
    static async addDomain(formData) {
        await ZhinaAPI.post('domains', formData);
        this.loadDomains(); // بروزرسانی خودکار لیست
    }

    // 5. ویرایش دامنه
    static async editDomain(id) {
        const domain = await ZhinaAPI.get(`domains/${id}`);
        document.getElementById('domainName').value = domain.name;
        document.getElementById('domainType').value = domain.type;
        document.getElementById('sslStatus').checked = domain.ssl_status;

        if (domain.type === 'subscription') {
            document.getElementById('subdomainsContainer').style.display = 'block';
        } else {
            document.getElementById('subdomainsContainer').style.display = 'none';
        }

        document.getElementById('domainFormContainer').style.display = 'block';
        // تغییر دکمه ارسال به "ویرایش"
        document.getElementById('domainForm').onsubmit = (event) => this.updateDomain(event, id);
    }

    // 6. ویرایش دامنه (پس از تغییر)
    static async updateDomain(event, id) {
        event.preventDefault();

        const formData = new FormData(event.target);
        const data = {
            name: formData.get('name'),
            type: formData.get('type'),
            ssl_status: formData.get('ssl_status') === 'on',
            subscription_id: formData.get('subdomains') || null
        };

        await ZhinaAPI.put(`domains/${id}`, data);
        this.loadDomains(); // بروزرسانی خودکار لیست
        document.getElementById('domainFormContainer').style.display = 'none';
    }

    // 7. حذف دامنه
    static async deleteDomain(id) {
        if (confirm('آیا مطمئنید؟')) {
            await ZhinaAPI.delete(`domains/${id}`);
            this.loadDomains(); // بروزرسانی خودکار لیست
        }
    }
}

// راه‌اندازی اولیه
document.addEventListener('DOMContentLoaded', () => {
    DomainManager.loadDomains();

    document.getElementById('addDomainBtn').addEventListener('click', () => {
        document.getElementById('domainFormContainer').style.display = 'block';
        document.getElementById('domainForm').onsubmit = (event) => DomainManager.addDomain(event.target);
    });

    document.getElementById('cancelDomainBtn').addEventListener('click', () => {
        document.getElementById('domainFormContainer').style.display = 'none';
    });
});
