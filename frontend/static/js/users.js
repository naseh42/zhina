class UserManager {
    static async init() {
        await this.loadUsers();
        this.setupEventListeners();
    }

    static async loadUsers() {
        const users = await ZhinaAPI.get('users');
        this.renderUsers(users);
    }

    static renderUsers(users) {
        const tbody = document.querySelector('#usersTable tbody');
        tbody.innerHTML = users.map(user => `
            <tr>
                <td>${user.username}</td>
                <td>${user.is_active ? 'فعال' : 'غیرفعال'}</td>
                <td>
                    <button class="btn-edit" data-id="${user.id}">ویرایش</button>
                    <button class="btn-delete" data-id="${user.id}">حذف</button>
                </td>
            </tr>
        `).join('');
    }

    static async deleteUser(userId) {
        if (confirm('آیا از حذف کاربر مطمئنید؟')) {
            await ZhinaAPI.delete(`users/${userId}`);
            await this.loadUsers();
        }
    }

    static setupEventListeners() {
        // حذف کاربر
        document.addEventListener('click', async (e) => {
            if (e.target.classList.contains('btn-delete')) {
                await this.deleteUser(e.target.dataset.id);
            }
        });

        // سایر لیسنرها...
    }
}

document.addEventListener('DOMContentLoaded', () => UserManager.init());
