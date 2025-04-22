// /static/js/settings.js
document.addEventListener('DOMContentLoaded', () => {
    // بارگذاری تنظیمات دامنه
    window.loadDomainSettings = async (domainId) => {
        const settings = await ZhinaAPI.fetch(`domains/${domainId}/settings`);
        document.getElementById('cdnProvider').value = settings.cdn_provider;
        document.getElementById('protocol').value = settings.protocol;
    };
});
