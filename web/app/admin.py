from django.contrib import admin
from .models import Contact

@admin.register(Contact)
class ContactAdmin(admin.ModelAdmin):
    list_display = ('name', 'email', 'recipient', 'subject', 'created_at')
    search_fields = ('email', 'name', 'subject')
    list_filter = ('recipient', 'created_at')