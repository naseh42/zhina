document.addEventListener('DOMContentLoaded', function () {
    const userList = document.getElementById('user-list');
    const searchInput = document.getElementById('search');
    const prevPageButton = document.getElementById('prev-page');
    const nextPageButton = document.getElementById('next-page');
    const header = document.getElementById('header');
    const pageTitle = document.getElementById('page-title');
    
    // Language data
    const langData = {
        fa: {
            pageTitle: "پنل مدیریت یوزرها",
            header: "مدیریت یوزرها",
            searchPlaceholder: "جستجو بر اساس اسم یا UUID...",
            usernameHeader: "نام یوزر",
            uuidHeader: "UUID",
            statusHeader: "وضعیت",
            dataUsageHeader: "حجم مصرفی",
            connectionsHeader: "تعداد اتصالات",
            lastConnectionHeader: "آخرین اتصال",
            actionsHeader: "عملیات",
            prevPage: "قبلی",
            nextPage: "بعدی",
        },
        en: {
            pageTitle: "User Management Panel",
            header: "User Management",
            searchPlaceholder: "Search by name or UUID...",
            usernameHeader: "Username",
            uuidHeader: "UUID",
            statusHeader: "Status",
            dataUsageHeader: "Data Usage",
            connectionsHeader: "Connections",
            lastConnectionHeader: "Last Connection",
            actionsHeader: "Actions",
            prevPage: "Previous",
            nextPage: "Next",
        }
    };

    let currentPage = 1;
    let usersPerPage = 50;
    let currentLang = 'fa'; // Default language is Persian

    // Function to change language
    function changeLanguage(lang) {
        currentLang = lang;
        const langContent = langData[lang];

        // Update text based on the selected language
        pageTitle.innerText = langContent.pageTitle;
        header.innerText = langContent.header;
        searchInput.placeholder = langContent.searchPlaceholder;

        document.getElementById('username-header').innerText = langContent.usernameHeader;
        document.getElementById('uuid-header').innerText = langContent.uuidHeader;
        document.getElementById('status-header').innerText = langContent.statusHeader;
        document.getElementById('data-usage-header').innerText = langContent.dataUsageHeader;
        document.getElementById('connections-header').innerText = langContent.connectionsHeader;
        document.getElementById('last-connection-header').innerText = langContent.lastConnectionHeader;
        document.getElementById('actions-header').innerText = langContent.actionsHeader;

        prevPageButton.innerText = langContent.prevPage;
        nextPageButton.innerText = langContent.nextPage;
    }

    // Event listeners for language buttons
    document.getElementById('btn-en').addEventListener('click', function () {
        changeLanguage('en');
    });

    document.getElementById('btn-fa').addEventListener('click', function () {
        changeLanguage('fa');
    });

    // Function to fetch users data (existing code)
    function fetchUsers(page = 1, searchTerm = '') {
        fetch(`/api/users?page=${page}&limit=${usersPerPage}&search=${searchTerm}`)
            .then(response => response.json())
            .then(data => {
                renderUsers(data.users);
                handlePagination(data.totalUsers);
            })
            .catch(error => console.error('Error fetching users:', error));
    }

    // Function to render users in the table (existing code)
    function renderUsers(users) {
        userList.innerHTML = '';
        users.forEach(user => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${user.name}</td>
                <td>${user.uuid}</td>
                <td>${user.online ? (currentLang === 'fa' ? 'آنلاین' : 'Online') : (currentLang === 'fa' ? 'آفلاین' : 'Offline')}</td>
                <td>${user.usedData} از ${user.totalData} گیگ</td>
                <td>${user.connections}</td>
                <td>${user.lastConnection}</td>
                <td>
                    <button onclick="viewUser(${user.id})">${currentLang === 'fa' ? 'مشاهده' : 'View'}</button>
                    <button onclick="editUser(${user.id})">${currentLang === 'fa' ? 'ویرایش' : 'Edit'}</button>
                    <button onclick="deleteUser(${user.id})">${currentLang === 'fa' ? 'حذف' : 'Delete'}</button>
                </td>
            `;
            userList.appendChild(row);
        });
    }

    // Handle pagination (existing code)
    function handlePagination(totalUsers) {
        const totalPages = Math.ceil(totalUsers / usersPerPage);
        prevPageButton.disabled = currentPage === 1;
        nextPageButton.disabled = currentPage === totalPages;
    }

    // Fetch users initially
    fetchUsers(currentPage);

    // Additional functions (view, edit, delete) as before
});
