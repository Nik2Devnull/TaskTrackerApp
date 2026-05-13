import psycopg2
import psycopg2.extras

DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'task_tracker_db',
    'user': '',
    'password': ''
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG)

def get_user_by_email(email):
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT user_id, email, full_name, role, password_hash 
                FROM users 
                WHERE email = %s AND status = 'active'
            """, (email,))
            return cur.fetchone()


def authenticate_user(email, password_hash):
    user = get_user_by_email(email)
    if user and user['password_hash'] == password_hash:
        return user
    return None


def register_user(creator_id, email, password_hash, full_name, role):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc('register_user', (creator_id, email, password_hash, full_name, role))
            user_id = cur.fetchone()[0]
            conn.commit()
            return user_id


def fire_user(admin_id, user_id):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc('fire_user', (admin_id, user_id))
            conn.commit()


def restore_user(admin_id, user_id):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc('restore_user', (admin_id, user_id))
            conn.commit()


def get_all_users():
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT user_id, full_name 
                FROM users 
                WHERE role = 'Employee' AND status = 'active'
                ORDER BY full_name
            """)
            return cur.fetchall()


def get_all_users_for_admin():
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.callproc('get_all_users')
            return cur.fetchall()


def get_all_teamleads_for_admin():
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT user_id, full_name, email,
                       (SELECT COUNT(*) FROM projects WHERE manager_id = users.user_id) as projects_count
                FROM users 
                WHERE role = 'TeamLead' AND status = 'active'
                ORDER BY full_name
            """)
            return cur.fetchall()


def get_all_employees_for_admin():
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT user_id, full_name, email,
                       (SELECT COUNT(*) FROM tasks WHERE assignee_id = users.user_id AND status_id IN (1,2,3)) as active_tasks_count
                FROM users 
                WHERE role = 'Employee' AND status = 'active'
                ORDER BY full_name
            """)
            return cur.fetchall()

def get_all_projects():
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT project_id, name FROM projects WHERE status = 'Active' ORDER BY name")
            return cur.fetchall()


def get_teamlead_projects(teamlead_id):
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT project_id, name, status, start_date, end_date
                FROM projects 
                WHERE manager_id = %s AND status = 'Active'
                ORDER BY name
            """, (teamlead_id,))
            return cur.fetchall()


def get_employee_projects(employee_id):
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT DISTINCT p.project_id, p.name, p.status, p.start_date, p.end_date
                FROM projects p
                JOIN tasks t ON p.project_id = t.project_id
                WHERE t.assignee_id = %s AND p.status = 'Active'
                ORDER BY p.name
            """, (employee_id,))
            return cur.fetchall()


def create_project_with_manager(admin_id, name, description, start_date, end_date, manager_id):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc('create_project_with_manager',
                        (admin_id, name, description, start_date, end_date, manager_id))
            project_id = cur.fetchone()[0]
            conn.commit()
            return project_id


def change_project_status(admin_id, project_id, new_status):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc('change_project_status', (admin_id, project_id, new_status))
            conn.commit()


def get_all_projects_with_managers():
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.callproc('get_all_projects_with_managers')
            return cur.fetchall()


def get_project_details(project_id):
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.callproc('get_project_details', (project_id,))
            return cur.fetchone()


def get_project_statistics(project_id):
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.callproc('get_project_statistics', (project_id,))
            return cur.fetchall()

def get_tasks_by_user(user_id, role_type):
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.callproc('get_tasks_by_user', (user_id, role_type))
            return cur.fetchall()


def create_task(title, description, due_date, estimated_hours, project_id, author_id, assignee_id, priority_id):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc('create_task', (title, description, due_date, estimated_hours, project_id, author_id, assignee_id, priority_id))
            task_id = cur.fetchone()[0]
            conn.commit()
            return task_id


def change_task_status(task_id, new_status_id, user_id):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc('set_current_user', (user_id,))
            cur.callproc('change_task_status', (task_id, new_status_id))
            conn.commit()


def assign_task(task_id, assignee_id):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc('assign_task', (task_id, assignee_id))
            conn.commit()


def get_task_details(task_id):
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.callproc('get_task_details', (task_id,))
            return cur.fetchone()


def get_tasks_by_project(project_id):
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT t.task_id, t.title, t.due_date,
                       ts.status_name, pri.priority_name,
                       u.full_name as assignee_name
                FROM tasks t
                JOIN task_statuses ts ON t.status_id = ts.status_id
                JOIN priorities pri ON t.priority_id = pri.priority_id
                LEFT JOIN users u ON t.assignee_id = u.user_id
                WHERE t.project_id = %s
                ORDER BY t.created_at DESC
            """, (project_id,))
            return cur.fetchall()

def add_comment(task_id, author_id, comment_text):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.callproc('add_comment_to_task', (task_id, author_id, comment_text))
            comment_id = cur.fetchone()[0]
            conn.commit()
            return comment_id


def get_comments_by_task(task_id):
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT c.comment_id, c.comment_text, c.created_at,
                       u.full_name as author_name, u.role as author_role
                FROM comments c
                JOIN users u ON c.author_id = u.user_id
                WHERE c.task_id = %s
                ORDER BY c.created_at ASC
            """, (task_id,))
            return cur.fetchall()


def get_all_tasks_for_comments(user_id, user_role):
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            if user_role == 'TeamLead':
                cur.execute("""
                    SELECT t.task_id, t.title, p.name as project_name, u.full_name as assignee_name
                    FROM tasks t
                    JOIN projects p ON t.project_id = p.project_id
                    LEFT JOIN users u ON t.assignee_id = u.user_id
                    WHERE p.manager_id = %s
                    ORDER BY p.name, t.task_id
                """, (user_id,))
            else:
                cur.execute("""
                    SELECT t.task_id, t.title, p.name as project_name, u.full_name as assignee_name
                    FROM tasks t
                    JOIN projects p ON t.project_id = p.project_id
                    LEFT JOIN users u ON t.assignee_id = u.user_id
                    WHERE t.assignee_id = %s OR t.author_id = %s
                    ORDER BY p.name, t.task_id
                """, (user_id, user_id))
            return cur.fetchall()

def get_all_statuses():
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT status_id, status_name FROM task_statuses ORDER BY status_id")
            return cur.fetchall()


def get_all_priorities():
    with get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT priority_id, priority_name, color FROM priorities ORDER BY priority_id")
            return cur.fetchall()