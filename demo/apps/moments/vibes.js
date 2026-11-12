(function () {
  'use strict';

  var topPostsSource = (function invoke(input) {
    var TOP_LIMIT = 5;
    var WINDOW_DAYS = 30;
    var rows = (input.data && input.data['posts.mine']) || [];
    var now = typeof input.now === 'number' ? input.now : Date.now();
    var dayMs = 86400000;
    var cutoff = now - WINDOW_DAYS * dayMs;

    var recent = [];
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (row && typeof row.postedAt === 'number' && row.postedAt >= cutoff) {
        recent.push(row);
      }
    }

    recent.sort(function (a, b) {
      return (b.likes || 0) - (a.likes || 0);
    });

    var top = recent.slice(0, TOP_LIMIT);
    var maxLikes = 1;
    for (var j = 0; j < top.length; j++) {
      var l = Number(top[j].likes || 0);
      if (l > maxLikes) {
        maxLikes = l;
      }
    }

    var headingText = TOP_LIMIT === 5 && WINDOW_DAYS === 30
      ? 'Top posts this month'
      : 'Top ' + TOP_LIMIT + ' posts \u00b7 last ' + WINDOW_DAYS + ' days';

    var children = [
      { type: 'heading', text: headingText }
    ];

    if (rows.length === 0) {
      children.push({ type: 'badge', text: 'No posts available', tone: 'warn' });
      children.push({ type: 'text', text: 'Moments did not return any posts yet.' });
    } else if (top.length === 0) {
      children.push({
        type: 'text',
        text: 'No posts in the last ' + WINDOW_DAYS + ' days.',
        tone: 'warn'
      });
    } else {
      for (var k = 0; k < top.length; k++) {
        var post = top[k];
        var rawCaption = String(post.caption || '');
        var label = rawCaption.length > 40 ? rawCaption.slice(0, 40) : rawCaption;
        var likes = Number(post.likes || 0);
        var days = Math.max(0, Math.floor((now - post.postedAt) / dayMs));
        children.push({
          type: 'bar',
          swatch: post.swatch,
          label: label,
          caption: likes + ' likes \u00b7 ' + days + ' days ago',
          value: likes,
          max: maxLikes
        });
      }
    }

    return {
      state: input.state || null,
      view: {
        type: 'column',
        children: children
      }
    };
  }).toString();

  var topFansSource = (function invoke(input) {
    var TOP_LIMIT = 5;
    var rows = (input.data && input.data['likes.byFollower']) || [];
    var sorted = rows.slice();
    sorted.sort(function (a, b) {
      return (b.count || 0) - (a.count || 0);
    });

    var top = sorted.slice(0, TOP_LIMIT);
    var maxCount = 1;
    for (var i = 0; i < top.length; i++) {
      var c = Number(top[i].count || 0);
      if (c > maxCount) {
        maxCount = c;
      }
    }

    var headingText = TOP_LIMIT === 5
      ? 'Your top fans'
      : 'Your top ' + TOP_LIMIT + ' fans';

    var children = [
      { type: 'heading', text: headingText },
      { type: 'text', text: 'Ranked without seeing who they are.' }
    ];

    if (top.length === 0) {
      children.push({ type: 'badge', text: 'No follower likes yet', tone: 'warn' });
      children.push({ type: 'text', text: 'Follower like counts are currently empty.' });
    } else {
      for (var j = 0; j < top.length; j++) {
        var row = top[j];
        var count = Number(row.count || 0);
        children.push({
          type: 'bar',
          label: row.follower,
          caption: count + ' likes',
          value: count,
          max: maxCount
        });
      }
    }

    return {
      state: input.state || null,
      view: {
        type: 'column',
        children: children
      }
    };
  }).toString();

  window.MOMENTS_VIBES = {
    topPosts: {
      id: 'top-posts',
      name: 'Top posts',
      wish: 'Show my top 5 posts this month',
      version: 1,
      needs: ['posts.mine'],
      refresh: 3000,
      source: topPostsSource
    },
    topFans: {
      id: 'top-fans',
      name: 'Top fans',
      wish: 'Who are my top fans?',
      version: 1,
      needs: ['likes.byFollower'],
      refresh: 3000,
      source: topFansSource
    }
  };
})();
