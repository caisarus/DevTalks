from flask import Flask, request, render_template_string, redirect, url_for, flash
import re

app = Flask(__name__)
app.secret_key = 'supersecretkey'  # Needed for flash messages

# In-memory phonebook data
phonebook = []

html_template = """
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <title>Phonebook</title>
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/css/bootstrap.min.css">
</head>
<body>
<div class="container">
    <h1 class="mt-5">Phonebook</h1>
    <form method="post" action="/add" class="mb-4">
        <div class="form-row">
            <div class="col">
                <input type="text" class="form-control" name="name" placeholder="Name" required>
            </div>
            <div class="col">
                <input type="text" class="form-control" name="phone" placeholder="Phone Number" required>
            </div>
            <div class="col">
                <input type="email" class="form-control" name="email" placeholder="Email Address" required>
            </div>
            <div class="col">
                <button type="submit" class="btn btn-primary">Add</button>
            </div>
        </div>
    </form>
    {% with messages = get_flashed_messages() %}
      {% if messages %}
        <div class="alert alert-warning" role="alert">
          {{ messages[0] }}
        </div>
      {% endif %}
    {% endwith %}
    <table class="table table-bordered">
        <thead>
            <tr>
                <th>Name</th>
                <th>Phone Number</th>
                <th>Email Address</th>
            </tr>
        </thead>
        <tbody>
            {% for entry in phonebook %}
            <tr>
                <td>{{ entry.name }}</td>
                <td>{{ entry.phone }}</td>
                <td>{{ entry.email }}</td>
            </tr>
            {% endfor %}
        </tbody>
    </table>
</div>
<script src="https://code.jquery.com/jquery-3.2.1.slim.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.11.0/umd/popper.min.js"></script>
<script src="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/js/bootstrap.min.js"></script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(html_template, phonebook=phonebook)

@app.route('/add', methods=['POST'])
def add_entry():
    name = request.form['name']
    phone = request.form['phone']
    email = request.form['email']
    
    # Validate phone number (only digits)
    if not re.match(r'^\d+$', phone):
        flash('Phone number should contain only digits.')
        return redirect(url_for('index'))
    
    # Validate email address
    if not re.match(r'^[^@]+@[^@]+\.[^@]+$', email):
        flash('Invalid email address format.')
        return redirect(url_for('index'))
    
    phonebook.append({'name': name, 'phone': phone, 'email': email})
    return redirect(url_for('index'))

if __name__ == '__main__':
    from waitress import serve
    serve(app, host='0.0.0.0', port=5000)
