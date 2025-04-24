document.addEventListener('DOMContentLoaded', function () {
    const userList = document.getElementById('user-list');
    const searchInput = document.getElementById('search');
    const prevPageButton = document.getElementById('prev-page');
    const nextPageButton = document.getElementById('next-page');
    let currentPage = 1;
    let usersPerPage = 50;

    // Function to fetch users data
    function fetchUsers(page = 1, searchTerm = '') {
        fetch(`/api/users?page=${page}&limit=${usersPerPage}&search=${searchTerm}`)
            .then(response => response.json())
            .then(data => {
                renderUsers(data.users);
                handlePagination(data.totalUsers);
            })
            .catch(error => console.error('Error fetching users:', error));
    }

    // Function to render users in the table
    function renderUsers(users) {
        userList.innerHTML = '';
        users.forEach(user => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${user.name}</td>
                <td>${user.uuid}</td>
                <td>${user.online ? 'آنلاین' : 'آفلاین'}</td>
                <td>${user.usedData} از ${user.totalData} گیگ</td>
                <td>${user.connections}</td>
                <td>${user.lastConnection}</td>
                <td>
                    <button onclick="viewUser(${user.id})">مشاهده</button>
                    <button onclick="editUser(${user.id})">ویرایش</button>
                    <button onclick="deleteUser(${user.id})">حذف</button>
                </td>
            `;
            userList.appendChild(row);
        });
    }

    // Handle pagination
    function handlePagination(totalUsers) {
        const totalPages = Math.ceil(totalUsers / usersPerPage);
        prevPageButton.disabled = currentPage === 1;
        nextPageButton.disabled = currentPage === totalPages;
    }

    // Event listener for search input
    searchInput.addEventListener('input', function () {
        currentPage = 1; // Reset to first page on search
        fetchUsers(currentPage, searchInput.value);
    });

    // Event listeners for pagination
    prevPageButton.addEventListener('click', function () {
        if (currentPage > 1) {
            currentPage--;
            fetchUsers(currentPage, searchInput.value);
        }
    });

    nextPageButton.addEventListener('click', function () {
        currentPage++;
        fetchUsers(currentPage, searchInput.value);
    });

    // Initial fetch
    fetchUsers(currentPage);

    // Functions for view, edit, and delete buttons
    window.viewUser = function (userId) {
        window.location.href = `/user/${userId}`; // Redirect to user page
    };

    window.editUser = function (userId) {
        // Implement edit functionality here
        alert('ویرایش یوزر: ' + userId);
    };

    window.deleteUser = function (userId) {
        // Implement delete functionality here
        if (confirm('آیا از حذف این یوزر مطمئن هستید؟')) {
            fetch(`/api/users/${userId}`, { method: 'DELETE' })
                .then(response => response.json())
                .then(data => {
                    alert('یوزر با موفقیت حذف شد');
                    fetchUsers(currentPage);
                })
                .catch(error => console.error('Error deleting user:', error));
        }
    };
});
