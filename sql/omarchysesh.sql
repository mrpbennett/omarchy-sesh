select id, created_at, label, capture_status, capture_error
from main.sessions
order by id;
--
select id, session, ord, class, initial_class, title, initial_title, cmdline, cwd,
       workspace_id, workspace_name, monitor_name, monitor_description,
       at_x, at_y, size_w, size_h, floating, fullscreen, pinned, xwayland,
       pid, group_id, group_ord
from main.windows
order by session desc, ord, id;
--
select session, workspace_id, layout, at_x, at_y, size_w, size_h,
       work_x, work_y, work_w, work_h, gap_top, gap_right, gap_bottom,
       gap_left, complete
from main.workspace_layouts
order by session, workspace_id;
--
select s.id, s.created_at, s.label, s.capture_status, s.capture_error,
       count(distinct w.id) as window_count,
       count(distinct wl.workspace_id) as layout_count
from sessions s
left join main.workspace_layouts wl on s.id = wl.session
left join main.windows w on s.id = w.session
group by s.id, s.created_at, s.label, s.capture_status, s.capture_error
order by s.id;
