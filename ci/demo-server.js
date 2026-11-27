'use strict';
// Демо-сервер для снимков экранов на GitHub Actions: те же адреса /api/…, что у torgana.ru, но с примерами
// объявлений, переписки и уведомлений (на боевом сайте может не быть объявлений, а вход нужен свой).
// Только для снимков: приложение в отладочной сборке запускается с -base http://127.0.0.1:8787.
const http = require('http');
const fs = require('fs');
const path = require('path');
const DIR = path.join(__dirname, 'demo');
const now = Date.now();
const H = 3600e3;
const config = JSON.parse(fs.readFileSync(path.join(DIR, 'config.json'), 'utf8'));

const seller = { id: 2, name: 'Анна Смирнова', avatar: null, level: 2, shop: false };
const me = { id: 1, name: 'Иван Тестов', email: 'ivan@example.com', avatar: null, isAdmin: true, phone: '', emailVerified: true,
  pushMessages: true, pushSearches: true, pushPrices: false, pushModeration: true, pushDeals: true, pushMoney: true, notifyMessages: true, notifyDigest: false, notifyModeration: true, createdAt: now - 20 * 24 * H,
  rep: { level: 1, levelName: 'Проверенный', deals: 3 }, badges: { official: false, shop: false, first: { no: 7, form: 'm', own: '' } }, deactivatedAt: null };
const items = [
  ['Велосипед Merida Big Nine 2023', 45000, 'Казань', 'hobby', 'hobby'], ['iPhone 15 Pro 256 ГБ, как новый', 89990, 'Москва', 'electronics', 'phones'],
  ['Диван угловой, раскладной', 18500, 'Казань', 'home', ''], ['Куртка зимняя Columbia, размер M', 7200, 'Москва', 'personal', ''],
  ['Lada Vesta 2021, 1.6 MT, один владелец', 1150000, 'Казань', 'transport', 'cars'], ['Детская коляска 3 в 1', 12000, 'Самара', 'personal', ''],
  ['Ноутбук MacBook Air M2 13"', 79000, 'Москва', 'electronics', ''], ['1-к квартира у метро, 38 м²', 35000, 'Москва', 'realty', '']
].map(([title, price, city, category, subcategory], i) => ({
  id: i + 1, title, price, priceUnit: category === 'realty' ? 'мес' : '', priceWas: i === 1 ? 95000 : null, city, metro: i === 7 ? 'Сокол' : '', category, subcategory,
  summary: '', photo: `/demo/p${i % 6}.jpg`, createdAt: now - i * 5 * H, isFav: i === 1 || i === 4, goodPrice: i === 4, delivery: i % 2 === 0, hasVideo: i === 4,
  status: 'active', boost: i === 1 ? { xl: false, frame: true, tags: [] } : null, seller
}));
const listing = (c) => ({
  listing: { ...c, metro: c.metro ? { name: c.metro, line: '2', color: '#4FB04F' } : null, description: 'Отличное состояние, всё работает. Торг уместен при осмотре. Самовывоз или доставка по городу.',
    condition: 'used', bargain: true, exchange: c.id === 5, views: 128, favCount: 9, updatedAt: c.createdAt, photos: [c.photo, `/demo/p${(c.id) % 6}.jpg`, `/demo/p${(c.id + 1) % 6}.jpg`],
    isOwner: false, specs: c.id === 5 ? [{ label: 'Марка', value: 'Lada' }, { label: 'Модель', value: 'Vesta' }, { label: 'Год выпуска', value: 2021 }, { label: 'Пробег', value: '48 000 км' }, { label: 'Коробка', value: 'Механика' }] : [{ label: 'Состояние', value: 'Б/у, отличное' }],
    rejectReason: '' },
  seller: { id: 2, name: 'Анна Смирнова', avatar: null, activeCount: 6, rep: { level: 2, levelName: 'Опытный', deals: 34 },
    badges: { official: false, shop: false, first: { no: 3, form: 'f' } }, followers: 12, following: false },
  similar: items.filter((x) => x.id !== c.id).slice(0, 4)
});
const conv = (id, it, name, other, lastBody, unread, hoursAgo, role, lastMine, status = 'active') => ({ id, listingId: it.id, title: it.title, price: it.price, priceUnit: it.priceUnit,
  status, photo: it.photo, other: { id: other, name, avatar: null }, lastBody, unread, updatedAt: now - hoursAgo * H, role, blocked: false, lastMine });
const convs = [
  conv(1, items[1], 'Анна Смирнова', 2, 'Да, могу показать завтра после 18:00', 2, 0.2, 'buyer', 0),
  conv(2, items[2], 'Олег', 3, 'Хорошо, завтра в 18:00 подойдёт', 0, 3, 'seller', 2),
  conv(3, items[2], 'Марина К.', 4, 'А доставка до Химок возможна?', 1, 26, 'seller', 0),
  conv(4, items[0], 'Дмитрий', 5, 'Предлагаю 42 000 ₽', 0, 50, 'seller', 1),
  conv(5, items[4], 'Сергей', 6, 'Спасибо, уже купил другую', 0, 120, 'buyer', 0, 'sold'),
  conv(6, items[6], 'Ирина', 7, 'Зарядка в комплекте?', 0, 150, 'buyer', 2)
];
const msgs = [
  { id: 1, mine: true, body: 'Здравствуйте! iPhone ещё продаётся?', photo: null, kind: '', offerId: null, reply: null, createdAt: now - 2 * H, read: true },
  { id: 2, mine: false, body: 'Здравствуйте! Да, продаётся. Аккумулятор 98%, полный комплект.', photo: null, kind: '', offerId: null, reply: null, createdAt: now - 1.8 * H, read: true },
  { id: 3, mine: true, body: 'Предлагаю 85 000 ₽ вместо 89 990 ₽', photo: null, kind: 'offer', offerId: 1, reply: null, createdAt: now - 1.5 * H, read: true },
  { id: 4, mine: false, body: 'Можно посмотреть вживую?', photo: null, kind: '', offerId: null, reply: { id: 1, mine: true, body: 'Здравствуйте! iPhone ещё продаётся?', photo: false, kind: '' }, createdAt: now - 0.4 * H, read: true },
  { id: 5, mine: false, body: 'Да, могу показать завтра после 18:00', photo: null, kind: '', offerId: null, reply: null, createdAt: now - 0.2 * H, read: true, editedAt: now - 0.15 * H },
  { id: 6, mine: true, body: '', photo: null, file: { url: '/demo/p0.jpg', name: 'Чек и гарантийный талон.pdf', size: 245760 }, kind: '', offerId: null, reply: null, createdAt: now - 0.1 * H, read: false }
];
const notices = [
  { id: 3, kind: 'price', title: 'Подешевело в избранном', body: '«iPhone 15 Pro 256 ГБ» — 89 990 ₽ вместо 95 000 ₽', url: '/l/2', icon: 'price', tone: '', at: now - 3 * H, read: false, photo: '' },
  { id: 2, kind: 'moderation', title: 'Объявление опубликовано', body: '«Велосипед Merida Big Nine 2023»', url: '/l/1', icon: 'check', tone: 'ok', at: now - 26 * H, read: false, photo: '' },
  { id: 1, kind: 'moderation', title: 'Медаль «Один из первых» — ваша!', body: 'Ваш номер — 7. Вы в первой тысяче продавцов Торганы', url: '/u/1', icon: 'medal', tone: 'ok', at: now - 50 * H, read: true, photo: '' }
];

const json = (res, data, status = 200) => { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(data)); };
http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  const p = u.pathname;
  if (!p.startsWith('/demo/')) console.log(new Date().toISOString().slice(11, 23), req.method, req.url);
  if (p.startsWith('/demo/')) { const f = path.join(DIR, path.basename(p)); if (fs.existsSync(f)) { res.writeHead(200, { 'Content-Type': 'image/jpeg' }); return fs.createReadStream(f).pipe(res); } }
  if (p === '/api/config') return json(res, config);
  if (p === '/api/listings/title') return json(res, { title: 'iPhone 15 Pro\u00a0· 256 ГБ' });
  // «Для бизнеса»: тариф «Магазин», витрина заполнена на 4 из 6, ИП ещё не проверен.
  if (p === '/api/my/business') return json(res, { plan: { id: 'shop', name: 'Магазин', until: now + 47 * 24 * H, trial: false }, biz: null,
    shop: { official: false, cover: '/demo/p1.jpg', about: 'Оригинальная техника Apple с гарантией. Доставка по России, самовывоз у метро.', hours: '10:00–21:00', address: 'Москва, Тверская, 12', site: '', delivery: '' },
    pinned: [], promotions: [{ id: 1, listingId: 2, title: 'iPhone 15 Pro 256 ГБ, как новый', status: 'active', endsAt: now + 6 * 24 * H, shows: 3120, clicks: 94, note: '' }],
    payments: [{ id: 2, title: 'Продвижение объявления на 7 дн. на Торгане', amount: 199, status: 'succeeded', method: 'Банковская карта', refunded: 0, createdAt: now - 24 * H },
      { id: 1, title: 'Тариф «Магазин» на Торгане, 1 мес. (30 дней)', amount: 490, status: 'succeeded', method: 'СБП', refunded: 0, createdAt: now - 13 * 24 * H }] });
  if (p === '/api/me/trademark') return json(res, { trademark: null, code: 'TG-4F2A9C', letter: 'Подтверждаю, что аккаунт ivan@example.com на сайте torgana.ru принадлежит ______ …\nКод заявки: TG-4F2A9C', docs: [], kinds: { cert: 'Свидетельство или выписка из реестра', letter: 'Письмо-подтверждение с кодом', power: 'Доверенность' } });
  if (p === '/api/my/shop/stats') { const n = Number(u.searchParams.get('days') || 30); return json(res, { period: n, totals: { impressions: 18400, views: 1240, favs: 41 }, prev: { impressions: 15100, views: 1410, favs: 38 },
    daily: Array.from({ length: n }, (_, i) => ({ day: `d${i}`, impressions: 500, views: 20 + Math.round(30 * Math.abs(Math.sin(i / 3))), favs: 1 })), active: 6,
    listings: items.slice(0, 5).map((x, i) => ({ id: x.id, title: x.title, photo: x.photo, views: 412 - i * 60, favs: 31 - i * 4, impressions: 4000 })) }); }
  if (p === '/api/me') return json(res, { user: me, unread: 2, notices: 2, fresh: { price: 1, follow: 0 } });
  if (p === '/api/listings') { const q = (u.searchParams.get('q') || '').toLowerCase(); const cat = u.searchParams.get('category'); const list = items.filter((x) => (!u.searchParams.get('user') || x.seller.id === Number(u.searchParams.get('user'))) && (!cat || x.category === cat) && (!q || q === 'а' || x.title.toLowerCase().includes(q))); return json(res, { items: list, total: list.length }); }
  let m = /^\/api\/listings\/(\d+)$/.exec(p);
  if (m) { const c = items.find((x) => x.id === Number(m[1])) || items[0]; return json(res, listing(c)); }
  if (p === '/api/favorites') return json(res, { items: items.filter((x) => x.isFav) });
  if (p === '/api/conversations') return json(res, { items: convs });
  m = /^\/api\/conversations\/(\d+)$/.exec(p);
  if (m) {
    const after = Number(u.searchParams.get('after') || 0);
    return json(res, { conversation: { id: 1, role: 'buyer' }, listing: { id: 2, title: items[1].title, price: items[1].price, priceUnit: '', status: 'active', bargain: true, photo: items[1].photo, city: 'Москва' },
      other: { id: 2, name: 'Анна Смирнова', avatar: null }, block: null, offers: [{ id: 1, price: 85000, listingPrice: 89990, status: 'pending', bySeller: false, parentId: null, createdAt: now - 1.5 * H }],
      readUpTo: 3, typing: true, messages: msgs.filter((x) => x.id > after) });
  }
  m = /^\/api\/users\/(\d+)$/.exec(p);
  if (m && m[1] === '3') return json(res, { user: { id: 3, name: 'Торгана', avatar: null, activeCount: 0, emailVerified: true, rep: { level: 0, levelName: 'Новичок', deals: 0, newbie: true, tags: [], marks: [] }, badges: { official: true }, followers: 0, following: false, block: null,
    shop: { official: true, name: 'Торгана', cover: null, about: 'Официальный аккаунт Торганы — площадки объявлений по всей России. Сторгуемся!\n\nРазмещать объявления — бесплатно и без лимитов, для частных лиц и для компаний. Каждое объявление проверяет модератор, а репутация продавца строится на подтверждённых сделках.\n\nЕсть вопрос или что-то пошло не так — напишите в «Поддержку Торганы» в «Сообщениях»: отвечают люди, а не бот.' } }, sections: [], pinned: [] });
  // свой профиль (/u/1) — с именем демо-пользователя, остальные — продавец Анна
  if (m) return json(res, { user: { ...listing(items[0]).seller, id: Number(m[1]), ...(m[1] === '1' ? { name: me.name, badges: me.badges } : {}), emailVerified: true, block: null }, sections: [], pinned: [] });
  if (p === '/api/pages/rules') return json(res, { title: 'Правила размещения', html: '<p>Все объявления на Торгане проходят модерацию. Объявление публикуется, если оно соответствует правилам.</p><h2>Запрещено</h2><ul><li>оружие и боеприпасы;</li><li>лекарства по рецепту;</li><li>поддельные товары.</li></ul><p>Подробнее — в <a href="/page/terms">пользовательском соглашении</a>.</p>' });
  if (p === '/api/support') return json(res, { messages: [] });
  if (p === '/api/my/listings') return json(res, { items: items.slice(0, 3).map((x, i) => ({ ...x, status: ['active', 'pending', 'active'][i], views: 40 + i * 13, favCount: i * 2, rejectReason: '' })) });
  if (p === '/api/admin/stats') return json(res, { pending: 4, reports: 2, support: 1, appeals: 0, biz: 0, rep: 0 });
  if (p === '/api/blocks') return json(res, { items: [{ id: 9, name: 'Спам-аккаунт', avatar: null, at: now - 3 * 24 * H }] });
  if (p === '/api/notices') return json(res, { items: notices, unread: 2 });
  if (p.startsWith('/api/')) return json(res, { ok: true });
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end('<!doctype html><meta name="viewport" content="width=device-width"><body style="font:16px -apple-system;padding:40px;color:#545A70">Страница сайта (на демо-сервере её нет)</body>');
}).listen(8787, '127.0.0.1', () => console.log('demo server :8787'));
