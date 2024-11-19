from django import forms

class UserForm(forms.Form):
    name = forms.CharField(
        max_length=100,
        label="Name",
        widget=forms.TextInput(attrs={'class': 'form-control'})
    )
    email = forms.EmailField(
        label="Email",
        widget=forms.EmailInput(attrs={'class': 'form-control'})
    )
    vpn_ip = forms.GenericIPAddressField(
        protocol='IPv4',
        label="VPN IP Address",
        widget=forms.TextInput(attrs={'class': 'form-control'})
    )
