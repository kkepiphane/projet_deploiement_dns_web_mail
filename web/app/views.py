from django.shortcuts import render
from django.core.mail import send_mail
from django.conf import settings
from .models import Contact

def home(request):
    return render(request, 'app/base.html')

def contact(request):
    if request.method == 'POST':
        email = request.POST.get('email')
        message = request.POST.get('message')
        
        Contact.objects.create(email=email, message=message)
        
        send_mail(
            'New Contact',
            message,
            email,
            [settings.ADMIN_EMAIL],
            fail_silently=False,
        )
        
    return render(request, 'app/contact.html')