/*
 * topbar-touch.js — 顶栏下拉菜单的触屏点击切换
 *
 * 鼠标设备靠 CSS :hover 展开即可；触屏没有 hover，需要「点一下展开、再点收起、
 * 点别处关闭」的三态。纯 CSS 做不到（:focus-within 会让菜单关不掉，[data-open]
 * 又是主题用来标记「当前所在栏目」的属性，不能借用）。
 *
 * 这里用独立属性 data-tap-open 控制，并且只在 (hover: none) 的设备上接管。
 */
(function () {
	'use strict';

	var mql = window.matchMedia('(hover: none)');
	if (!mql.matches)
		return;

	function init() {
		var sidebar = document.getElementById('sidebar');
		if (!sidebar)
			return;

		var items = sidebar.querySelectorAll('.sidebar-accordion-item');
		if (!items.length)
			return;

		function closeAll(except) {
			items.forEach(function (item) {
				if (item !== except)
					item.removeAttribute('data-tap-open');
			});
		}

		items.forEach(function (item) {
			var trigger = item.querySelector('.sidebar-nav-parent');
			if (!trigger || trigger.dataset.tapBound === '1')
				return;
			trigger.dataset.tapBound = '1';

			trigger.addEventListener('click', function (ev) {
				var open = item.getAttribute('data-tap-open') === 'true';

				// 阻止默认的「聚焦后仍保留 hover 状态」行为
				ev.preventDefault();
				ev.stopPropagation();

				if (open) {
					item.removeAttribute('data-tap-open');
				}
				else {
					closeAll(item);
					item.setAttribute('data-tap-open', 'true');
				}
			});
		});

		// 点菜单外任意位置 → 全部收起
		document.addEventListener('click', function (ev) {
			if (ev.target.closest && ev.target.closest('.sidebar-accordion-item'))
				return;
			closeAll(null);
		}, true);

		// 切页时收起
		window.addEventListener('hashchange', function () { closeAll(null); });
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', init);
	else
		init();
})();
