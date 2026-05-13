import psycopg2
from flask import Flask, render_template, request, redirect, url_for, session, flash
import db

app = Flask(__name__)
app.secret_key = 'PWD1143'

@app.route('/')
def index():
    if 'user_id' in session:
        return redirect(url_for('dashboard'))
    return redirect(url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        email = request.form['email']
        password = request.form['password']
        user = db.authenticate_user(email, password)
        if user:
            session['user_id'] = user['user_id']
            session['user_name'] = user['full_name']
            session['user_role'] = user['role']
            session['user_email'] = user['email']
            flash(f'Добро пожаловать, {user["full_name"]}!', 'success')
            return redirect(url_for('dashboard'))
        else:
            flash('Неверный email или пароль', 'danger')
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    flash('Вы вышли из системы', 'info')
    return redirect(url_for('login'))


@app.route('/dashboard')
def dashboard():
    if 'user_id' not in session:
        return redirect(url_for('login'))

    projects = []

    if session['user_role'] == 'TeamLead':
        projects = db.get_teamlead_projects(session['user_id'])
    elif session['user_role'] == 'Employee':
        projects = db.get_employee_projects(session['user_id'])
    else:
        projects = db.get_all_projects()

    return render_template('dashboard.html',
                           user_name=session['user_name'],
                           user_role=session['user_role'],
                           projects=projects)

@app.route('/my_tasks')
def my_tasks():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    tasks = db.get_tasks_by_user(session['user_id'], 'assignee')
    statuses = db.get_all_statuses()
    return render_template('my_tasks.html',
                           tasks=tasks,
                           statuses=statuses,
                           user_role=session['user_role'])

@app.route('/tasks')
def tasks():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'TeamLead':
        flash('Доступ запрещён', 'danger')
        return redirect(url_for('dashboard'))
    tasks = db.get_tasks_by_user(session['user_id'], 'manager')
    statuses = db.get_all_statuses()
    return render_template('tasks.html',
                           tasks=tasks,
                           statuses=statuses)

@app.route('/change_status/<int:task_id>', methods=['POST'])
def change_status(task_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))
    new_status_id = request.form.get('status_id')
    if new_status_id:
        try:
            db.change_task_status(task_id, int(new_status_id), session['user_id'])
            flash('Статус задачи успешно изменён', 'success')
        except Exception as e:
            flash(f'Ошибка: {str(e)}', 'danger')
    referer = request.referrer
    return redirect(referer or url_for('dashboard'))

@app.route('/create_task', methods=['GET', 'POST'])
def create_task_view():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'TeamLead':
        flash('Доступ запрещён', 'danger')
        return redirect(url_for('dashboard'))
    if request.method == 'POST':
        title = request.form['title']
        description = request.form['description']
        due_date = request.form['due_date'] or None
        estimated_hours = request.form['estimated_hours'] or None
        project_id = request.form['project_id']
        assignee_id = request.form.get('assignee_id') or None
        priority_id = request.form['priority_id']
        try:
            task_id = db.create_task(
                title, description, due_date, estimated_hours,
                int(project_id), session['user_id'],
                int(assignee_id) if assignee_id else None,
                int(priority_id)
            )
            flash(f'Задача "{title}" успешно создана!', 'success')
            return redirect(url_for('tasks'))
        except Exception as e:
            flash(f'Ошибка при создании задачи: {str(e)}', 'danger')
    projects = db.get_teamlead_projects(session['user_id'])
    users = db.get_all_users()
    priorities = db.get_all_priorities()
    return render_template('create_task.html',
                           projects=projects,
                           users=users,
                           priorities=priorities)

@app.route('/assign_task', methods=['GET', 'POST'])
def assign_task_view():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'TeamLead':
        flash('Доступ запрещён', 'danger')
        return redirect(url_for('dashboard'))
    if request.method == 'POST':
        task_id = request.form['task_id']
        assignee_id = request.form['assignee_id']
        try:
            db.assign_task(int(task_id), int(assignee_id))
            flash('Исполнитель успешно назначен', 'success')
        except Exception as e:
            flash(f'Ошибка: {str(e)}', 'danger')
        return redirect(url_for('assign_task_view'))
    tasks = db.get_tasks_by_user(session['user_id'], 'manager')
    users = db.get_all_users()
    unassigned_tasks = [t for t in tasks if not t['assignee_name']]
    return render_template('assign_task.html',
                           tasks=unassigned_tasks,
                           users=users)

@app.route('/statistics')
def statistics():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'TeamLead':
        flash('Доступ запрещён', 'danger')
        return redirect(url_for('dashboard'))
    projects = db.get_teamlead_projects(session['user_id'])
    stats_data = {}
    for project in projects:
        stats = db.get_project_statistics(project['project_id'])
        stats_dict = {}
        for stat in stats:
            stats_dict[stat['metric_name']] = stat['metric_value']
        stats_data[project['name']] = stats_dict
    return render_template('statistics.html',
                           stats_data=stats_data,
                           projects=projects)

@app.route('/comments')
def comments_list():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    tasks = db.get_all_tasks_for_comments(session['user_id'], session['user_role'])
    return render_template('comments_list.html', tasks=tasks, user_role=session['user_role'])

@app.route('/comments/<int:task_id>')
def comments_view(task_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))
    with db.get_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT t.task_id, t.title, p.name as project_name,
                       assignee.full_name as assignee_name,
                       author.full_name as author_name
                FROM tasks t
                JOIN projects p ON t.project_id = p.project_id
                LEFT JOIN users assignee ON t.assignee_id = assignee.user_id
                JOIN users author ON t.author_id = author.user_id
                WHERE t.task_id = %s
            """, (task_id,))
            task = cur.fetchone()
    if not task:
        flash('Задача не найдена', 'danger')
        return redirect(url_for('comments_list'))
    comments = db.get_comments_by_task(task_id)
    return render_template('comments_view.html',
                           task=task,
                           comments=comments,
                           user_id=session['user_id'],
                           user_name=session['user_name'],
                           user_role=session['user_role'])

@app.route('/comments/<int:task_id>/add', methods=['POST'])
def comments_add(task_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))
    comment_text = request.form.get('comment_text', '').strip()
    if not comment_text:
        flash('Комментарий не может быть пустым', 'danger')
        return redirect(url_for('comments_view', task_id=task_id))
    try:
        db.add_comment(task_id, session['user_id'], comment_text)
        flash('Комментарий успешно добавлен', 'success')
    except Exception as e:
        flash(f'Ошибка: {str(e)}', 'danger')
    return redirect(url_for('comments_view', task_id=task_id))

@app.route('/admin/users')
def admin_users():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'Admin':
        flash('Доступ запрещён. Только для администратора.', 'danger')
        return redirect(url_for('dashboard'))
    users = db.get_all_users_for_admin()
    employees = db.get_all_employees_for_admin()
    teamleads = db.get_all_teamleads_for_admin()
    return render_template('admin_users.html',
                           users=users,
                           employees=employees,
                           teamleads=teamleads,
                           admin_id=session['user_id'])

@app.route('/admin/register', methods=['GET', 'POST'])
def admin_register():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'Admin':
        flash('Доступ запрещён. Только для администратора.', 'danger')
        return redirect(url_for('dashboard'))
    if request.method == 'POST':
        email = request.form['email']
        password_hash = request.form['password_hash']
        full_name = request.form['full_name']
        role = request.form['role']
        try:
            user_id = db.register_user(session['user_id'], email, password_hash, full_name, role)
            flash(f'Пользователь "{full_name}" успешно зарегистрирован!', 'success')
            return redirect(url_for('admin_users'))
        except Exception as e:
            flash(f'Ошибка: {str(e)}', 'danger')
    return render_template('admin_register.html')


@app.route('/admin/fire_user/<int:user_id>', methods=['POST'])
def admin_fire_user(user_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'Admin':
        flash('Доступ запрещён. Только для администратора.', 'danger')
        return redirect(url_for('dashboard'))
    try:
        db.fire_user(session['user_id'], user_id)
        flash('Пользователь успешно уволен', 'success')
    except Exception as e:
        flash(f'Ошибка: {str(e)}', 'danger')
    return redirect(url_for('admin_users'))

@app.route('/admin/restore_user/<int:user_id>', methods=['POST'])
def admin_restore_user(user_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'Admin':
        flash('Доступ запрещён. Только для администратора.', 'danger')
        return redirect(url_for('dashboard'))
    try:
        db.restore_user(session['user_id'], user_id)
        flash('Пользователь успешно восстановлен', 'success')
    except Exception as e:
        flash(f'Ошибка: {str(e)}', 'danger')
    return redirect(url_for('admin_users'))

@app.route('/admin/projects')
def admin_projects():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'Admin':
        flash('Доступ запрещён. Только для администратора.', 'danger')
        return redirect(url_for('dashboard'))
    projects = db.get_all_projects_with_managers()
    teamleads = db.get_all_teamleads_for_admin()
    return render_template('admin_projects.html',
                           projects=projects,
                           teamleads=teamleads,
                           admin_id=session['user_id'])

@app.route('/admin/create_project', methods=['POST'])
def admin_create_project():
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'Admin':
        flash('Доступ запрещён. Только для администратора.', 'danger')
        return redirect(url_for('dashboard'))
    name = request.form['name']
    description = request.form.get('description', '')
    start_date = request.form.get('start_date') or None
    end_date = request.form.get('end_date') or None
    manager_id = request.form['manager_id']
    try:
        project_id = db.create_project_with_manager(
            session['user_id'], name, description, start_date, end_date, int(manager_id)
        )
        flash(f'Проект "{name}" успешно создан!', 'success')
    except Exception as e:
        flash(f'Ошибка: {str(e)}', 'danger')
    return redirect(url_for('admin_projects'))

@app.route('/admin/change_project_status/<int:project_id>', methods=['POST'])
def admin_change_project_status(project_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))
    if session['user_role'] != 'Admin':
        flash('Доступ запрещён. Только для администратора.', 'danger')
        return redirect(url_for('dashboard'))
    new_status = request.form['new_status']
    try:
        db.change_project_status(session['user_id'], project_id, new_status)
        flash(f'Статус проекта успешно изменён на "{new_status}"', 'success')
    except Exception as e:
        flash(f'Ошибка: {str(e)}', 'danger')
    return redirect(url_for('admin_projects'))


@app.route('/project/<int:project_id>')
def view_project(project_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))

    project = db.get_project_details(project_id)

    if not project:
        flash('Проект не найден', 'danger')
        return redirect(url_for('dashboard'))

    user_role = session['user_role']
    user_id = session['user_id']

    can_view = False
    if user_role == 'Admin':
        can_view = True
    elif user_role == 'TeamLead':
        can_view = (project['manager_id'] == user_id)
    elif user_role == 'Employee':
        with db.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT 1 FROM tasks 
                    WHERE project_id = %s AND assignee_id = %s
                    LIMIT 1
                """, (project_id, user_id))
                can_view = cur.fetchone() is not None

    if not can_view:
        flash('У вас нет доступа к этому проекту', 'danger')
        return redirect(url_for('dashboard'))

    tasks = db.get_tasks_by_project(project_id)

    return render_template('view_project.html',
                           project=project,
                           tasks=tasks,
                           user_role=user_role)


@app.route('/task/<int:task_id>')
def view_task(task_id):
    if 'user_id' not in session:
        return redirect(url_for('login'))

    task = db.get_task_details(task_id)

    if not task:
        flash('Задача не найдена', 'danger')
        return redirect(url_for('dashboard'))

    user_role = session['user_role']
    user_id = session['user_id']

    can_view = False
    if user_role == 'Admin':
        can_view = True
    elif user_role == 'TeamLead':
        with db.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT 1 FROM projects 
                    WHERE project_id = %s AND manager_id = %s
                """, (task['project_id'], user_id))
                can_view = cur.fetchone() is not None
    elif user_role == 'Employee':
        can_view = (task['assignee_id'] == user_id or task['author_id'] == user_id)

    if not can_view:
        flash('У вас нет доступа к этой задаче', 'danger')
        return redirect(url_for('dashboard'))

    return render_template('view_task.html', task=task, user_role=user_role)

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5001)