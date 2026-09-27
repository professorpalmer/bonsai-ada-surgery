const PRODUCT = { sku: "harbor-mug", name: "Harbor Mug", total: "$36.00" };

function cart() {
  try {
    return JSON.parse(localStorage.getItem("sandbox-cart") || "null");
  } catch {
    return null;
  }
}

function setCart(item) {
  localStorage.setItem("sandbox-cart", JSON.stringify(item));
}

function params() {
  return new URLSearchParams(window.location.search);
}

function fillSuccess() {
  const order = document.getElementById("order-id");
  if (!order) return;
  const id = params().get("order") || "ORDER PENDING";
  order.textContent = id;
  const item = params().get("item") || PRODUCT.name;
  const total = params().get("total") || PRODUCT.total;
  const last4 = params().get("last4") || "4242";
  const name = params().get("name") || "Ada Lovelace";
  const set = (idName, value) => {
    const el = document.getElementById(idName);
    if (el) el.textContent = value;
  };
  set("ok-item", item);
  set("ok-total", total);
  set("ok-last4", last4);
  set("ok-name", name);
}

function wireShop() {
  const add = document.getElementById("add-to-cart");
  const go = document.getElementById("go-checkout");
  const status = document.getElementById("cart-status");
  if (!add || !go || !status) return;
  const show = () => {
    const item = cart();
    if (!item) return;
    status.textContent = `Cart: ${item.name} x1 — ${item.total}`;
    go.classList.remove("hidden");
  };
  show();
  add.addEventListener("click", () => {
    setCart(PRODUCT);
    show();
  });
}

function digits(value) {
  return String(value || "").replace(/\D/g, "");
}

function wireCheckout() {
  const form = document.getElementById("checkout-form");
  if (!form) return;
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const status = document.getElementById("form-status");
    const body = {
      sku: PRODUCT.sku,
      item: PRODUCT.name,
      total: PRODUCT.total,
      full_name: form.full_name.value.trim(),
      email: form.email.value.trim(),
      address: form.address.value.trim(),
      card_number: digits(form.card_number.value),
      expiry: form.expiry.value.trim(),
      cvc: form.cvc.value.trim(),
    };
    if (status) status.textContent = "Placing sandbox order...";
    const resp = await fetch("/api/checkout", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const data = await resp.json();
    if (!resp.ok) {
      if (status) status.textContent = data.error || "Checkout refused.";
      return;
    }
    localStorage.removeItem("sandbox-cart");
    const q = new URLSearchParams({
      order: data.order_id,
      item: data.item,
      total: data.total,
      last4: data.last4,
      name: data.full_name,
    });
    window.location.href = `/success.html?${q.toString()}`;
  });
}

fillSuccess();
wireShop();
wireCheckout();
