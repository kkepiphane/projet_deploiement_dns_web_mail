from django.shortcuts import render, redirect
from django.core.mail import send_mail
from django.conf import settings
from django.contrib import messages
from .models import Contact

def home(request):
    if request.method == 'POST':
        _handle_contact_submission(request)
        return redirect('home')
    return render(request, 'app/base.html')

def contact(request):
    if request.method == 'POST':
        _handle_contact_submission(request)
        return redirect('contact')
    return render(request, 'contact/contact.html')

def _handle_contact_submission(request):
    name = request.POST.get('name', '')
    email = request.POST.get('email')
    subject = request.POST.get('subject', '')
    message = request.POST.get('message')
    recipient = request.POST.get('recipient', 'contact')

    if not email or not message:
        messages.error(request, "Merci de renseigner votre email et votre message.")
        return

    Contact.objects.create(
        name=name, email=email, subject=subject,
        recipient=recipient, message=message,
    )

    to_email = settings.INFO_EMAIL if recipient == 'info' else settings.ADMIN_EMAIL
    send_mail(
        subject or 'Nouveau message depuis le site',
        f"De : {name} <{email}>\n\n{message}",
        settings.DEFAULT_FROM_EMAIL,
        [to_email],
        fail_silently=False,
    )
    messages.success(request, "Votre message a bien été envoyé, merci !")