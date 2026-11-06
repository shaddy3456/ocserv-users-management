import re

from django import forms
from django.utils import timezone

from .models import * 

USERNAME_RE = re.compile(r"[A-Za-z0-9_.][A-Za-z0-9_.-]{0,15}")


class AddUserForm(forms.ModelForm):

    class Meta:
        model = OcservUser
        exclude = ('oc_active',)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for field in self.fields:
            self.fields[field].widget.attrs.update({'class': 'form-control'})
        self.fields['desc'].widget.attrs.update({"rows" : '8'})

    def clean_oc_username(self):
        oc_username = self.cleaned_data['oc_username']
        if not USERNAME_RE.fullmatch(oc_username):
            raise forms.ValidationError(
                "Username may only contain letters, digits, '.', '_' and '-' and must not start with '-'"
            )
        obj = OcservUser.objects.filter(oc_username=oc_username)
        if obj.exists():
            raise forms.ValidationError("username is already exist".title())
        return oc_username

    def clean_oc_password(self):
        oc_password = self.cleaned_data['oc_password']
        if any(c in oc_password for c in "\r\n\x00:"):
            raise forms.ValidationError("Password must not contain new lines or ':'")
        return oc_password

    def clean_expire_date(self):
        expire_date = self.cleaned_data['expire_date']  
        if expire_date and expire_date <= timezone.now().date():
            raise forms.ValidationError("the expiration date cannot be less than or equal the current date".title())
        return expire_date