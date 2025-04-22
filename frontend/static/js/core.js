// /static/js/core.js
class ZhinaAPI {
    static async fetch(endpoint, method = 'GET', data = null) {
        const options = {
            method,
            headers: {'Content-Type': 'application/json'},
            body: data ? JSON.stringify(data) : null
        };
        
        try {
            const response = await fetch(`/api/v1/${endpoint}`, options);
            return await response.json();
        } catch (error) {
            console.error('API Error:', error);
            throw error;
        }
    }

    static showLoader() {
        document.querySelectorAll('.stat-value').forEach(el => {
            el.textContent = '...';
        });
    }

    static formatTraffic(bytes) {
        return (bytes / 1024 ** 3).toFixed(2) + ' GB';
    }
}

// توابع مودال
function openModal(modalId) {
    document.getElementById(modalId).style.display = 'block';
}

function closeModal(modalId) {
    document.getElementById(modalId).style.display = 'none';
}
