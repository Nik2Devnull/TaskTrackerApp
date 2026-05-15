DROP TABLE IF EXISTS task_status_history CASCADE;
DROP TABLE IF EXISTS task_tags CASCADE;
DROP TABLE IF EXISTS comments CASCADE;
DROP TABLE IF EXISTS tasks CASCADE;
DROP TABLE IF EXISTS projects CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS task_statuses CASCADE;
DROP TABLE IF EXISTS priorities CASCADE;
DROP TABLE IF EXISTS tags CASCADE;

DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE;
DROP FUNCTION IF EXISTS check_task_due_date() CASCADE;
DROP FUNCTION IF EXISTS log_task_status_change() CASCADE;
DROP FUNCTION IF EXISTS current_user_id() CASCADE;
DROP FUNCTION IF EXISTS set_current_user(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS create_task(VARCHAR, TEXT, DATE, NUMERIC, INTEGER, INTEGER, INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS assign_task(INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS change_task_status(INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS add_comment_to_task(INTEGER, INTEGER, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_tasks_by_user(INTEGER, VARCHAR) CASCADE;
DROP FUNCTION IF EXISTS get_project_statistics(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS register_user(INTEGER, VARCHAR, VARCHAR, VARCHAR, VARCHAR) CASCADE;
DROP FUNCTION IF EXISTS fire_user(INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS restore_user(INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS create_project_with_manager(INTEGER, VARCHAR, TEXT, DATE, DATE, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS change_project_status(INTEGER, INTEGER, VARCHAR) CASCADE;
DROP FUNCTION IF EXISTS get_all_users() CASCADE;
DROP FUNCTION IF EXISTS get_all_projects_with_managers() CASCADE;
DROP FUNCTION IF EXISTS get_task_details(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS get_project_details(INTEGER) CASCADE;

CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('Employee', 'TeamLead', 'Admin')),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'fired')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE task_statuses (
    status_id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(200)
);

CREATE TABLE priorities (
    priority_id SERIAL PRIMARY KEY,
    priority_name VARCHAR(50) NOT NULL UNIQUE,
    color VARCHAR(7)
);

CREATE TABLE projects (
    project_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    start_date DATE,
    end_date DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Completed', 'Archived')),
    manager_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tasks (
    task_id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    due_date DATE,
    estimated_hours NUMERIC(5,2),
    project_id INTEGER NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    author_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    assignee_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    status_id INTEGER NOT NULL REFERENCES task_statuses(status_id) ON DELETE RESTRICT,
    priority_id INTEGER NOT NULL REFERENCES priorities(priority_id) ON DELETE RESTRICT
);

CREATE TABLE comments (
    comment_id SERIAL PRIMARY KEY,
    task_id INTEGER NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
    author_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    comment_text TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tags (
    tag_id SERIAL PRIMARY KEY,
    tag_name VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(200)
);

CREATE TABLE task_tags (
    task_id INTEGER REFERENCES tasks(task_id) ON DELETE CASCADE,
    tag_id INTEGER REFERENCES tags(tag_id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, tag_id)
);

CREATE TABLE task_status_history (
    history_id SERIAL PRIMARY KEY,
    task_id INTEGER NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
    old_status_id INTEGER REFERENCES task_statuses(status_id),
    new_status_id INTEGER NOT NULL REFERENCES task_statuses(status_id) ON DELETE RESTRICT,
    changed_by INTEGER NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_tasks_assignee ON tasks(assignee_id);
CREATE INDEX idx_tasks_project ON tasks(project_id);
CREATE INDEX idx_tasks_status ON tasks(status_id);
CREATE INDEX idx_comments_task ON comments(task_id);
CREATE INDEX idx_task_tags_task ON task_tags(task_id);
CREATE INDEX idx_task_tags_tag ON task_tags(tag_id);
CREATE INDEX idx_task_status_history_task ON task_status_history(task_id);


-- Триггеры --

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_tasks_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE FUNCTION check_task_due_date()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.due_date IS NOT NULL AND NEW.due_date < CURRENT_DATE THEN
        RAISE EXCEPTION 'Due date cannot be earlier than current date. Provided: %', NEW.due_date;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_task_due_date
    BEFORE INSERT OR UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION check_task_due_date();

CREATE OR REPLACE FUNCTION current_user_id()
RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(current_setting('app.current_user_id', TRUE)::INTEGER, 1);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION log_task_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status_id IS DISTINCT FROM NEW.status_id THEN
        INSERT INTO task_status_history (task_id, old_status_id, new_status_id, changed_by)
        VALUES (NEW.task_id, OLD.status_id, NEW.status_id, current_user_id());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_log_task_status_change
    AFTER UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION log_task_status_change();

-- Процедуры --


CREATE OR REPLACE FUNCTION set_current_user(p_user_id INTEGER)
RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_user_id', p_user_id::TEXT, FALSE);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION register_user(
    p_creator_id INTEGER,
    p_email VARCHAR(100),
    p_password_hash VARCHAR(255),
    p_full_name VARCHAR(150),
    p_role VARCHAR(20)
)
RETURNS INTEGER AS $$
DECLARE
    v_user_id INTEGER;
    v_creator_role VARCHAR(20);
BEGIN
    SELECT role INTO v_creator_role FROM users WHERE user_id = p_creator_id;
    
    IF v_creator_role != 'Admin' THEN
        RAISE EXCEPTION 'Only Admin can register new users';
    END IF;
    
    IF p_role = 'Admin' THEN
        RAISE EXCEPTION 'Cannot create another Admin';
    END IF;
    
    IF p_role NOT IN ('Employee', 'TeamLead') THEN
        RAISE EXCEPTION 'Invalid role. Must be Employee or TeamLead';
    END IF;
    
    IF EXISTS (SELECT 1 FROM users WHERE email = p_email) THEN
        RAISE EXCEPTION 'User with email % already exists', p_email;
    END IF;
    
    INSERT INTO users (email, password_hash, full_name, role, status)
    VALUES (p_email, p_password_hash, p_full_name, p_role, 'active')
    RETURNING user_id INTO v_user_id;
    
    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION fire_user(p_admin_id INTEGER, p_user_id INTEGER)
RETURNS VOID AS $$
DECLARE
    v_admin_role VARCHAR(20);
    v_target_role VARCHAR(20);
BEGIN
    SELECT role INTO v_admin_role FROM users WHERE user_id = p_admin_id;
    IF v_admin_role != 'Admin' THEN
        RAISE EXCEPTION 'Only Admin can fire users';
    END IF;
    
    IF p_admin_id = p_user_id THEN
        RAISE EXCEPTION 'Cannot fire yourself';
    END IF;
    
    SELECT role INTO v_target_role FROM users WHERE user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User with id % does not exist', p_user_id;
    END IF;
    
    IF v_target_role = 'Admin' THEN
        RAISE EXCEPTION 'Cannot fire another Admin';
    END IF;
    
    UPDATE users SET status = 'fired' WHERE user_id = p_user_id;
    UPDATE users SET password_hash = 'FIRED_USER' WHERE user_id = p_user_id;
    
    RAISE NOTICE 'User % (ID: %) has been fired', p_user_id, p_user_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION restore_user(p_admin_id INTEGER, p_user_id INTEGER)
RETURNS VOID AS $$
DECLARE
    v_admin_role VARCHAR(20);
    v_target_status VARCHAR(20);
BEGIN
    SELECT role INTO v_admin_role FROM users WHERE user_id = p_admin_id;
    IF v_admin_role != 'Admin' THEN
        RAISE EXCEPTION 'Only Admin can restore users';
    END IF;
    
    SELECT status INTO v_target_status FROM users WHERE user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User with id % does not exist', p_user_id;
    END IF;
    
    IF v_target_status != 'fired' THEN
        RAISE EXCEPTION 'User is not fired (status: %)', v_target_status;
    END IF;
    
    UPDATE users SET status = 'active' WHERE user_id = p_user_id;
    UPDATE users SET password_hash = 'NEED_RESET' WHERE user_id = p_user_id;
    
    RAISE NOTICE 'User % (ID: %) has been restored', p_user_id, p_user_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_task(
    p_title VARCHAR(200),
    p_description TEXT,
    p_due_date DATE,
    p_estimated_hours NUMERIC(5,2),
    p_project_id INTEGER,
    p_author_id INTEGER,
    p_assignee_id INTEGER DEFAULT NULL,
    p_priority_id INTEGER DEFAULT 2
)
RETURNS INTEGER AS $$
DECLARE
    v_task_id INTEGER;
    v_default_status_id INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM projects WHERE project_id = p_project_id) THEN
        RAISE EXCEPTION 'Project with id % does not exist', p_project_id;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_author_id) THEN
        RAISE EXCEPTION 'Author with id % does not exist', p_author_id;
    END IF;
    
    IF p_assignee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_assignee_id) THEN
        RAISE EXCEPTION 'Assignee with id % does not exist', p_assignee_id;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM priorities WHERE priority_id = p_priority_id) THEN
        RAISE EXCEPTION 'Priority with id % does not exist', p_priority_id;
    END IF;
    
    SELECT status_id INTO v_default_status_id FROM task_statuses WHERE status_name = 'Новая';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Default status "Новая" not found';
    END IF;
    
    INSERT INTO tasks (title, description, due_date, estimated_hours,
                       project_id, author_id, assignee_id, status_id, priority_id)
    VALUES (p_title, p_description, p_due_date, p_estimated_hours,
            p_project_id, p_author_id, p_assignee_id, v_default_status_id, p_priority_id)
    RETURNING task_id INTO v_task_id;
    
    RETURN v_task_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION assign_task(
    p_task_id INTEGER,
    p_assignee_id INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_current_status_id INTEGER;
    v_status_name VARCHAR(50);
BEGIN
    SELECT status_id INTO v_current_status_id FROM tasks WHERE task_id = p_task_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task with id % does not exist', p_task_id;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_assignee_id) THEN
        RAISE EXCEPTION 'User with id % does not exist', p_assignee_id;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_assignee_id AND role = 'Employee' AND status = 'active') THEN
        RAISE EXCEPTION 'Only active Employee can be assigned as task executor';
    END IF;
    
    SELECT status_name INTO v_status_name FROM task_statuses WHERE status_id = v_current_status_id;
    IF v_status_name IN ('Готова', 'Отменена') THEN
        RAISE EXCEPTION 'Cannot assign executor to task with status %', v_status_name;
    END IF;
    
    UPDATE tasks SET assignee_id = p_assignee_id WHERE task_id = p_task_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION change_task_status(
    p_task_id INTEGER,
    p_new_status_id INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_current_status_id INTEGER;
    v_current_status_name VARCHAR(50);
    v_new_status_name VARCHAR(50);
    v_current_user_id INTEGER;
    v_current_user_role VARCHAR(20);
BEGIN
    v_current_user_id := current_user_id();
    SELECT role INTO v_current_user_role FROM users WHERE user_id = v_current_user_id;
    
    SELECT status_id, assignee_id INTO v_current_status_id FROM tasks WHERE task_id = p_task_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task with id % does not exist', p_task_id;
    END IF;
    
    SELECT status_name INTO v_new_status_name FROM task_statuses WHERE status_id = p_new_status_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Status with id % does not exist', p_new_status_id;
    END IF;
    
    SELECT status_name INTO v_current_status_name FROM task_statuses WHERE status_id = v_current_status_id;
    
    IF p_new_status_id IN (4, 5) AND v_current_user_role != 'TeamLead' THEN
        RAISE EXCEPTION 'Only TeamLead can change status to "%"', v_new_status_name;
    END IF;
    
    IF v_current_status_name = 'Новая' AND p_new_status_id NOT IN (2, 5) THEN
        RAISE EXCEPTION 'From "Новая" can only go to "В работе" or "Отменена"';
    END IF;
    
    IF v_current_status_name = 'В работе' AND p_new_status_id NOT IN (3, 5) THEN
        RAISE EXCEPTION 'From "В работе" can only go to "На проверке" or "Отменена"';
    END IF;
    
    IF v_current_status_name = 'На проверке' AND p_new_status_id NOT IN (2, 4) THEN
        RAISE EXCEPTION 'From "На проверке" can only go to "В работе" or "Готова"';
    END IF;
    
    IF v_current_status_name IN ('Готова', 'Отменена') THEN
        RAISE EXCEPTION 'Task with status "%" cannot be changed', v_current_status_name;
    END IF;
    
    UPDATE tasks SET status_id = p_new_status_id WHERE task_id = p_task_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION add_comment_to_task(
    p_task_id INTEGER,
    p_author_id INTEGER,
    p_comment_text TEXT
)
RETURNS INTEGER AS $$
DECLARE
    v_comment_id INTEGER;
    v_assignee_id INTEGER;
    v_author_id INTEGER;
    v_manager_id INTEGER;
    v_project_id INTEGER;
BEGIN
    SELECT assignee_id, author_id, project_id INTO v_assignee_id, v_author_id, v_project_id
    FROM tasks WHERE task_id = p_task_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task with id % does not exist', p_task_id;
    END IF;
    
    SELECT manager_id INTO v_manager_id FROM projects WHERE project_id = v_project_id;
    
    IF p_author_id NOT IN (v_assignee_id, v_author_id, v_manager_id) THEN
        RAISE EXCEPTION 'User % is not authorized to comment on task %', p_author_id, p_task_id;
    END IF;
    
    INSERT INTO comments (task_id, author_id, comment_text)
    VALUES (p_task_id, p_author_id, p_comment_text)
    RETURNING comment_id INTO v_comment_id;
    
    RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_tasks_by_user(
    p_user_id INTEGER,
    p_role_type VARCHAR(20) DEFAULT 'assignee'
)
RETURNS TABLE (
    task_id INTEGER,
    title VARCHAR(200),
    project_name VARCHAR(200),
    status_name VARCHAR(50),
    priority_name VARCHAR(50),
    priority_color VARCHAR(7),
    due_date DATE,
    assignee_name VARCHAR(150),
    author_name VARCHAR(150),
    estimated_hours NUMERIC(5,2)
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id) THEN
        RAISE EXCEPTION 'User with id % does not exist', p_user_id;
    END IF;
    
    IF p_role_type = 'assignee' THEN
        RETURN QUERY
        SELECT t.task_id, t.title, pr.name, ts.status_name, pri.priority_name, pri.color,
               t.due_date, assignee.full_name, author.full_name, t.estimated_hours
        FROM tasks t
        JOIN projects pr ON t.project_id = pr.project_id
        JOIN task_statuses ts ON t.status_id = ts.status_id
        JOIN priorities pri ON t.priority_id = pri.priority_id
        LEFT JOIN users assignee ON t.assignee_id = assignee.user_id
        JOIN users author ON t.author_id = author.user_id
        WHERE t.assignee_id = p_user_id
        ORDER BY pri.priority_id DESC, t.due_date NULLS LAST;
    
    ELSIF p_role_type = 'author' THEN
        RETURN QUERY
        SELECT t.task_id, t.title, pr.name, ts.status_name, pri.priority_name, pri.color,
               t.due_date, assignee.full_name, author.full_name, t.estimated_hours
        FROM tasks t
        JOIN projects pr ON t.project_id = pr.project_id
        JOIN task_statuses ts ON t.status_id = ts.status_id
        JOIN priorities pri ON t.priority_id = pri.priority_id
        LEFT JOIN users assignee ON t.assignee_id = assignee.user_id
        JOIN users author ON t.author_id = author.user_id
        WHERE t.author_id = p_user_id
        ORDER BY t.created_at DESC;
    
    ELSIF p_role_type = 'manager' THEN
        RETURN QUERY
        SELECT t.task_id, t.title, pr.name, ts.status_name, pri.priority_name, pri.color,
               t.due_date, assignee.full_name, author.full_name, t.estimated_hours
        FROM tasks t
        JOIN projects pr ON t.project_id = pr.project_id
        JOIN task_statuses ts ON t.status_id = ts.status_id
        JOIN priorities pri ON t.priority_id = pri.priority_id
        LEFT JOIN users assignee ON t.assignee_id = assignee.user_id
        JOIN users author ON t.author_id = author.user_id
        WHERE pr.manager_id = p_user_id
        ORDER BY pr.name, t.due_date NULLS LAST;
    ELSE
        RAISE EXCEPTION 'Invalid role_type. Use: assignee, author, manager';
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_project_statistics(p_project_id INTEGER)
RETURNS TABLE (metric_name VARCHAR(100), metric_value TEXT) AS $$
DECLARE
    v_total_tasks INTEGER;
    v_completed_tasks INTEGER;
    v_cancelled_tasks INTEGER;
    v_in_progress_tasks INTEGER;
    v_overdue_tasks INTEGER;
    v_avg_completion_days NUMERIC(10,2);
    v_project_name VARCHAR(200);
BEGIN
    SELECT name INTO v_project_name FROM projects WHERE project_id = p_project_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Project with id % does not exist', p_project_id;
    END IF;
    
    SELECT COUNT(*) INTO v_total_tasks FROM tasks WHERE project_id = p_project_id;
    
    SELECT COUNT(*) INTO v_completed_tasks 
    FROM tasks t JOIN task_statuses ts ON t.status_id = ts.status_id
    WHERE t.project_id = p_project_id AND ts.status_name = 'Готова';
    
    SELECT COUNT(*) INTO v_cancelled_tasks 
    FROM tasks t JOIN task_statuses ts ON t.status_id = ts.status_id
    WHERE t.project_id = p_project_id AND ts.status_name = 'Отменена';
    
    SELECT COUNT(*) INTO v_in_progress_tasks 
    FROM tasks t JOIN task_statuses ts ON t.status_id = ts.status_id
    WHERE t.project_id = p_project_id AND ts.status_name IN ('Новая', 'В работе', 'На проверке');
    
    SELECT COUNT(*) INTO v_overdue_tasks 
    FROM tasks t JOIN task_statuses ts ON t.status_id = ts.status_id
    WHERE t.project_id = p_project_id AND t.due_date < CURRENT_DATE 
      AND ts.status_name NOT IN ('Готова', 'Отменена');
    
    SELECT AVG(EXTRACT(DAY FROM (t.updated_at - t.created_at))) INTO v_avg_completion_days
    FROM tasks t JOIN task_statuses ts ON t.status_id = ts.status_id
    WHERE t.project_id = p_project_id AND ts.status_name = 'Готова';
    
    metric_name := 'Название проекта'; metric_value := v_project_name; RETURN NEXT;
    metric_name := 'Всего задач'; metric_value := v_total_tasks::TEXT; RETURN NEXT;
    metric_name := 'Выполнено'; metric_value := v_completed_tasks::TEXT; RETURN NEXT;
    metric_name := 'Отменено'; metric_value := v_cancelled_tasks::TEXT; RETURN NEXT;
    metric_name := 'В работе'; metric_value := v_in_progress_tasks::TEXT; RETURN NEXT;
    metric_name := 'Просрочено'; metric_value := v_overdue_tasks::TEXT; RETURN NEXT;
    metric_name := 'Процент выполнения'; 
    metric_value := ROUND(v_completed_tasks::NUMERIC / NULLIF(v_total_tasks, 0) * 100, 2)::TEXT || '%'; 
    RETURN NEXT;
    metric_name := 'Среднее время выполнения (дней)'; 
    metric_value := COALESCE(ROUND(v_avg_completion_days, 2), 0)::TEXT; 
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_project_with_manager(
    p_admin_id INTEGER,
    p_name VARCHAR(200),
    p_description TEXT,
    p_start_date DATE,
    p_end_date DATE,
    p_manager_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_project_id INTEGER;
    v_admin_role VARCHAR(20);
    v_manager_role VARCHAR(20);
BEGIN
    SELECT role INTO v_admin_role FROM users WHERE user_id = p_admin_id;
    IF v_admin_role != 'Admin' THEN
        RAISE EXCEPTION 'Only Admin can create projects';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_manager_id AND status = 'active') THEN
        RAISE EXCEPTION 'Manager with id % does not exist or is not active', p_manager_id;
    END IF;
    
    SELECT role INTO v_manager_role FROM users WHERE user_id = p_manager_id;
    IF v_manager_role != 'TeamLead' THEN
        RAISE EXCEPTION 'Project manager must have TeamLead role';
    END IF;
    
    IF EXISTS (SELECT 1 FROM projects WHERE name = p_name) THEN
        RAISE EXCEPTION 'Project with name "%" already exists', p_name;
    END IF;
    
    IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_start_date > p_end_date THEN
        RAISE EXCEPTION 'Start date cannot be later than end date';
    END IF;
    
    INSERT INTO projects (name, description, start_date, end_date, status, manager_id)
    VALUES (p_name, p_description, p_start_date, p_end_date, 'Active', p_manager_id)
    RETURNING project_id INTO v_project_id;
    
    RETURN v_project_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION change_project_status(
    p_admin_id INTEGER,
    p_project_id INTEGER,
    p_new_status VARCHAR(20)
)
RETURNS VOID AS $$
DECLARE
    v_admin_role VARCHAR(20);
    v_current_status VARCHAR(20);
BEGIN
    SELECT role INTO v_admin_role FROM users WHERE user_id = p_admin_id;
    IF v_admin_role != 'Admin' THEN
        RAISE EXCEPTION 'Only Admin can change project status';
    END IF;
    
    SELECT status INTO v_current_status FROM projects WHERE project_id = p_project_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Project with id % does not exist', p_project_id;
    END IF;
    
    IF p_new_status NOT IN ('Active', 'Completed', 'Archived') THEN
        RAISE EXCEPTION 'Invalid status. Use: Active, Completed, Archived';
    END IF;
    
    IF v_current_status = 'Archived' AND p_new_status != 'Archived' THEN
        RAISE EXCEPTION 'Cannot unarchive a project';
    END IF;
    
    UPDATE projects SET status = p_new_status WHERE project_id = p_project_id;
    
    RAISE NOTICE 'Project % status changed from % to %', p_project_id, v_current_status, p_new_status;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_all_users()
RETURNS TABLE (
    user_id INTEGER,
    email VARCHAR(100),
    full_name VARCHAR(150),
    role VARCHAR(20),
    status VARCHAR(20),
    created_at TIMESTAMP,
    active_tasks_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.user_id,
        u.email,
        u.full_name,
        u.role,
        u.status,
        u.created_at,
        COUNT(t.task_id) FILTER (WHERE t.status_id IN (1,2,3) AND t.assignee_id = u.user_id)::BIGINT AS active_tasks_count
    FROM users u
    LEFT JOIN tasks t ON u.user_id = t.assignee_id
    GROUP BY u.user_id, u.email, u.full_name, u.role, u.status, u.created_at
    ORDER BY 
        CASE u.status 
            WHEN 'active' THEN 1 
            ELSE 2 
        END,
        CASE u.role 
            WHEN 'Admin' THEN 1
            WHEN 'TeamLead' THEN 2
            ELSE 3
        END,
        u.full_name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_all_projects_with_managers()
RETURNS TABLE (
    project_id INTEGER,
    name VARCHAR(200),
    description TEXT,
    status VARCHAR(20),
    start_date DATE,
    end_date DATE,
    created_at TIMESTAMP,
    manager_id INTEGER,
    manager_name VARCHAR(150),
    manager_status VARCHAR(20),
    total_tasks BIGINT,
    completed_tasks BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.project_id,
        p.name::VARCHAR(200),
        p.description,
        p.status::VARCHAR(20),
        p.start_date,
        p.end_date,
        p.created_at,
        u.user_id,
        u.full_name::VARCHAR(150),
        u.status::VARCHAR(20),
        COUNT(DISTINCT t.task_id)::BIGINT,
        COUNT(DISTINCT CASE WHEN ts.status_name = 'Готова' THEN t.task_id END)::BIGINT
    FROM projects p
    LEFT JOIN users u ON p.manager_id = u.user_id
    LEFT JOIN tasks t ON p.project_id = t.project_id
    LEFT JOIN task_statuses ts ON t.status_id = ts.status_id
    GROUP BY p.project_id, p.name, p.description, p.status, p.start_date, p.end_date, p.created_at, u.user_id, u.full_name, u.status
    ORDER BY p.project_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_task_details(p_task_id INTEGER)
RETURNS TABLE (
    task_id INTEGER,
    title VARCHAR(200),
    description TEXT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    due_date DATE,
    estimated_hours NUMERIC(5,2),
    project_id INTEGER,
    project_name VARCHAR(200),
    project_description TEXT,
    author_id INTEGER,
    author_name VARCHAR(150),
    assignee_id INTEGER,
    assignee_name VARCHAR(150),
    status_id INTEGER,
    status_name VARCHAR(50),
    priority_id INTEGER,
    priority_name VARCHAR(50),
    priority_color VARCHAR(7),
    tags TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.task_id,
        t.title,
        t.description,
        t.created_at,
        t.updated_at,
        t.due_date,
        t.estimated_hours,
        p.project_id,
        p.name::VARCHAR(200),
        p.description,
        author.user_id,
        author.full_name::VARCHAR(150),
        assignee.user_id,
        assignee.full_name::VARCHAR(150),
        ts.status_id,
        ts.status_name::VARCHAR(50),
        pri.priority_id,
        pri.priority_name::VARCHAR(50),
        pri.color::VARCHAR(7),
        COALESCE(tag_list.tags, '')::TEXT
    FROM tasks t
    JOIN projects p ON t.project_id = p.project_id
    JOIN users author ON t.author_id = author.user_id
    LEFT JOIN users assignee ON t.assignee_id = assignee.user_id
    JOIN task_statuses ts ON t.status_id = ts.status_id
    JOIN priorities pri ON t.priority_id = pri.priority_id
    LEFT JOIN (
        SELECT tt.task_id, STRING_AGG(tg.tag_name, ', ') as tags
        FROM task_tags tt
        JOIN tags tg ON tt.tag_id = tg.tag_id
        GROUP BY tt.task_id
    ) tag_list ON t.task_id = tag_list.task_id
    WHERE t.task_id = p_task_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_project_details(p_project_id INTEGER)
RETURNS TABLE (
    project_id INTEGER,
    name VARCHAR(200),
    description TEXT,
    start_date DATE,
    end_date DATE,
    status VARCHAR(20),
    created_at TIMESTAMP,
    manager_id INTEGER,
    manager_name VARCHAR(150),
    total_tasks BIGINT,
    completed_tasks BIGINT,
    active_tasks BIGINT,
    team_members BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.project_id,
        p.name::VARCHAR(200),
        p.description,
        p.start_date,
        p.end_date,
        p.status::VARCHAR(20),
        p.created_at,
        manager.user_id,
        manager.full_name::VARCHAR(150),
        COUNT(DISTINCT t.task_id)::BIGINT,
        COUNT(DISTINCT CASE WHEN ts.status_name = 'Готова' THEN t.task_id END)::BIGINT,
        COUNT(DISTINCT CASE WHEN ts.status_name IN ('Новая', 'В работе', 'На проверке') THEN t.task_id END)::BIGINT,
        COUNT(DISTINCT u.user_id)::BIGINT
    FROM projects p
    LEFT JOIN users manager ON p.manager_id = manager.user_id
    LEFT JOIN tasks t ON p.project_id = t.project_id
    LEFT JOIN task_statuses ts ON t.status_id = ts.status_id
    LEFT JOIN users u ON t.assignee_id = u.user_id
    WHERE p.project_id = p_project_id
    GROUP BY p.project_id, p.name, p.description, p.start_date, p.end_date, p.status, p.created_at, manager.user_id, manager.full_name;
END;
$$ LANGUAGE plpgsql;