// /static/js/domains.js
document.addEventListener('DOMContentLoaded', () => {
    // حذف دامنه
    window.deleteDomain = async (domainId) => {
        if (confirm('آیا مطمئنید؟')) {
            await ZhinaAPI.fetch(`domains/${domainId}`, 'DELETE');
            location.reload();
        }
    };
});
