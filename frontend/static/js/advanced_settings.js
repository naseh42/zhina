document.addEventListener("DOMContentLoaded", function () {
  fetchInbounds();
});

function fetchInbounds() {
  fetch("/api/xray/inbounds")
    .then(res => res.json())
    .then(data => renderInbounds(data))
    .catch(err => console.error("خطا در بارگذاری اینباندها:", err));
}

function renderInbounds(inbounds) {
  const container = document.getElementById("inbounds-list");
  container.innerHTML = "";

  if (inbounds.length === 0) {
    container.innerHTML = "<p>هیچ اینباندی ثبت نشده است.</p>";
    return;
  }

  inbounds.forEach(inbound => {
    const card = document.createElement("div");
    card.className = "p-4 bg-gray-100 rounded shadow";

    card.innerHTML = `
      <div class="flex justify-between items-center mb-2">
        <h4 class="font-semibold">${inbound.tag}</h4>
        <div class="flex gap-2">
          <button onclick='editInbound(${JSON.stringify(inbound)})' class="btn btn-sm btn-info">ویرایش</button>
          <button onclick='deleteInbound("${inbound.id}")' class="btn btn-sm btn-error">حذف</button>
        </div>
      </div>
      <p><strong>پورت:</strong> ${inbound.port}</p>
      <p><strong>پروتکل:</strong> ${inbound.protocol}</p>
      <p><strong>TLS:</strong> ${inbound.tls}</p>
      <p><strong>سابسکرپشن:</strong> ${inbound.subscription}</p>
    `;

    container.appendChild(card);
  });
}

function openInboundModal() {
  document.getElementById("inbound-form").reset();
  document.getElementById("inbound-id").value = "";
  document.getElementById("inbound-modal-title").innerText = "افزودن اینباند";
  document.getElementById("inbound-modal").classList.remove("hidden");
}

function closeInboundModal() {
  document.getElementById("inbound-modal").classList.add("hidden");
}

function editInbound(inbound) {
  document.getElementById("inbound-id").value = inbound.id;
  document.getElementById("inbound-tag").value = inbound.tag;
  document.getElementById("inbound-port").value = inbound.port;
  document.getElementById("inbound-protocol").value = inbound.protocol;
  document.getElementById("inbound-tls").value = inbound.tls;
  document.getElementById("inbound-subscription").value = inbound.subscription;
  document.getElementById("inbound-modal-title").innerText = "ویرایش اینباند";
  document.getElementById("inbound-modal").classList.remove("hidden");
}

function submitInbound(event) {
  event.preventDefault();
  const formData = new FormData(event.target);
  const data = Object.fromEntries(formData.entries());

  const method = data.id ? "PUT" : "POST";
  const url = data.id ? `/api/xray/inbounds/${data.id}` : "/api/xray/inbounds";

  fetch(url, {
    method: method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data)
  })
    .then(res => {
      if (!res.ok) throw new Error("خطا در ذخیره اینباند");
      return res.json();
    })
    .then(() => {
      closeInboundModal();
      fetchInbounds();
    })
    .catch(err => {
      alert("خطا در ذخیره: " + err.message);
      console.error(err);
    });
}

function deleteInbound(id) {
  if (!confirm("آیا مطمئن هستید که می‌خواهید اینباند حذف شود؟")) return;

  fetch(`/api/xray/inbounds/${id}`, { method: "DELETE" })
    .then(res => {
      if (!res.ok) throw new Error("خطا در حذف اینباند");
      return res.json();
    })
    .then(() => fetchInbounds())
    .catch(err => {
      alert("خطا در حذف: " + err.message);
      console.error(err);
    });
}
