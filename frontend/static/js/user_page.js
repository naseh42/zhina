document.addEventListener('DOMContentLoaded', function () {
    const userNameElement = document.getElementById('user-name');
    const dataRemainingElement = document.getElementById('data-remaining');
    const dataUsedElement = document.getElementById('data-used');
    const dataChartElement = document.getElementById('usage-bar');
    const usageTextElement = document.getElementById('usage-text');
    const configsListElement = document.getElementById('configs-list');
    const subscriptionLinkElement = document.getElementById('subscription-url');
    const qrCodeElement = document.getElementById('qr-image');
    const configContentElement = document.getElementById('config-content');

    // Example data for the user
    const user = {
        name: "ناصح پیران",
        remainingData: 100,
        usedData: 50,
        configs: [
            { name: "VLESS", config: "config-vless-xyz", uuid: "123-abc" },
            { name: "VMess", config: "config-vmess-xyz", uuid: "456-def" },
            { name: "Trojan", config: "config-trojan-xyz", uuid: "789-ghi" }
        ],
        subscriptionLink: "https://example.com/subscription-link",
        qrCodeSrc: "/static/images/qr-placeholder.png"
    };

    // Function to display user data
    function displayUserData() {
        userNameElement.innerText = user.name;
        dataRemainingElement.innerText = `حجم باقی‌مانده: ${user.remainingData} گیگ`;
        dataUsedElement.innerText = `حجم مصرفی: ${user.usedData} گیگ`;

        // Calculate usage percentage
        const usagePercentage = (user.usedData / user.remainingData) * 100;
        dataChartElement.style.width = `${usagePercentage}%`;
        usageTextElement.innerText = `${user.usedData} گیگ از ${user.remainingData} گیگ مصرف شده`;

        // Set subscription link
        subscriptionLinkElement.href = user.subscriptionLink;

        // Set QR code image source
        qrCodeElement.src = user.qrCodeSrc;

        // Display configs
        user.configs.forEach(config => {
            const listItem = document.createElement('li');
            listItem.innerHTML = `<a href="#" class="config-link" data-config="${config.config}">${config.name}</a>`;
            configsListElement.appendChild(listItem);
        });
    }

    // Function to handle config link click
    function handleConfigClick(event) {
        if (event.target.classList.contains('config-link')) {
            const configContent = event.target.getAttribute('data-config');
            configContentElement.textContent = configContent;
            configContentElement.style.display = 'block'; // Show config content
        }
    }

    // Function to copy config to clipboard
    function copyConfigToClipboard() {
        const range = document.createRange();
        range.selectNode(configContentElement);
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
        document.execCommand('copy');
        alert("کانفیگ کپی شد!");
    }

    // Add event listener for config link click
    configsListElement.addEventListener('click', handleConfigClick);

    // Add event listener for copying config
    configContentElement.addEventListener('click', copyConfigToClipboard);

    // Display user data on page load
    displayUserData();
});
