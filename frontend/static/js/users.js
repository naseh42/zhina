// /static/js/users.js
document.addEventListener('DOMContentLoaded', () => {
    // مدیریت مودال‌ها
    window.openAddUserModal = () => openModal('addUserModal');
    window.closeAddUserModal = () => closeModal('addUserModal');
    
    // فرم افزودن کاربر
    document.getElementById('addUserForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const formData = new FormData(e.target);
        await ZhinaAPI.fetch('users', 'POST', Object.fromEntries(formData));
        location.reload();
    });
});
