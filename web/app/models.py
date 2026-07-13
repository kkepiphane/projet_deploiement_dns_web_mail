from django.db import models

class Contact(models.Model):
    RECIPIENT_CHOICES = [
        ('contact', 'Contact commercial'),
        ('info', 'Renseignements'),
    ]

    name = models.CharField(max_length=255, blank=True)
    email = models.EmailField()
    subject = models.CharField(max_length=255, blank=True)
    recipient = models.CharField(max_length=10, choices=RECIPIENT_CHOICES, default='contact')
    message = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.email